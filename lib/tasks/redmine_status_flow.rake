# Rake tasks for the Redmine Status Flow plugin.
#
# Plugin migrations are tracked in the shared `schema_migrations` table under
# "<version>-<plugin_id>". Renaming the plugin id (redmine_status_history ->
# redmine_status_flow) therefore hides already-applied migrations from
# Redmine, which would replay them on the next `redmine:plugins:migrate`.
# `adopt_legacy_identity` rewrites those rows so an existing installation
# upgrading from upstream keeps its migration state.
#
# The historical backfill lives here (not in a migration) on purpose: as a
# migration it ran Issue.find_each with N+1 journal loading inside a single
# transaction, which locked the issues table for hours on large installations
# and could not be resumed after a failure.
module RedmineStatusFlowTasks
  COLUMNS = %i[issue_id status_id previous_status_id journal_id user_id from to].freeze

  module_function

  def from_column(table_alias)
    "#{table_alias}.#{ActiveRecord::Base.connection.quote_column_name('from')}"
  end

  def orphan_scope
    IssueStatusHistory.where.not(journal_id: nil).where(
      'journal_id NOT IN (SELECT journal_id FROM journal_details WHERE journal_id IS NOT NULL)'
    )
  end

  # A last_status_update that is behind the newest interval is stale (a status
  # change never reached the column). One that is a few microseconds ahead is
  # not: the issue's initial row takes its date from created_on, which rounds
  # differently from the timestamp written at insert time.
  def stale_scope
    Issue.where(
      "last_status_update IS NULL OR last_status_update < " \
      "(SELECT MAX(#{from_column('ish')}) FROM issue_status_histories ish WHERE ish.issue_id = issues.id)"
    )
  end

  # Builds the intervals of the given issues from their journal details and
  # inserts them in chunks. Returns the number of rows written.
  def rebuild_batch(issue_ids)
    return 0 if issue_ids.empty?

    journals = Journal.where(journalized_type: 'Issue', journalized_id: issue_ids)
                      .includes(:details)
                      .order(:created_on, :id)
                      .group_by(&:journalized_id)
    issues = Issue.where(id: issue_ids).index_by(&:id)

    rows = []
    issue_ids.each do |issue_id|
      issue = issues[issue_id]
      next unless issue

      changes = (journals[issue_id] || []).flat_map do |journal|
        journal.details
               .select { |d| d.property == 'attr' && d.prop_key == 'status_id' }
               .map { |d| [journal, d] }
      end

      if changes.empty?
        rows << { issue_id: issue.id, from: issue.created_on, status_id: issue.status_id,
                  user_id: issue.author_id }
        next
      end

      first_journal, first_detail = changes.first
      rows << { issue_id: issue.id, from: issue.created_on, to: first_journal.created_on,
                status_id: first_detail.old_value.presence || issue.status_id,
                user_id: issue.author_id }

      changes.each do |journal, detail|
        changed_at = journal.created_on
        rows.last[:to] = changed_at
        rows << { issue_id: issue.id, from: changed_at, status_id: detail.value,
                  user_id: journal.user_id, journal_id: journal.id,
                  previous_status_id: detail.old_value }
      end
    end

    normalized = rows.map { |row| COLUMNS.index_with { |column| row[column] } }
    normalized.each_slice(200) { |slice| IssueStatusHistory.insert_all(slice) }
    refresh_last_status_update(issue_ids)
    normalized.size
  end

  # last_status_update = newest interval start, recomputed in one statement.
  def refresh_last_status_update(issue_ids)
    return if issue_ids.empty?

    quoted = issue_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(',')
    ActiveRecord::Base.connection.execute(<<~SQL)
      UPDATE issues
      SET last_status_update = COALESCE(
        (SELECT MAX(#{from_column('ish')}) FROM issue_status_histories ish WHERE ish.issue_id = issues.id),
        issues.created_on
      )
      WHERE issues.id IN (#{quoted})
    SQL
  end

  def repair_last_status_update
    ids = stale_scope.pluck(:id)
    ids.each_slice(500) { |slice| refresh_last_status_update(slice) }
    ids.size
  end
end

namespace :redmine_status_flow do
  desc 'Adopt migration rows recorded under the legacy redmine_status_history plugin id'
  task adopt_legacy_identity: :environment do
    legacy_id = 'redmine_status_history'
    new_id    = 'redmine_status_flow'

    connection = ActiveRecord::Base.connection
    sm_table   = connection.pool.schema_migration.table_name
    legacy_versions = connection.select_values(
      "SELECT version FROM #{sm_table} WHERE version LIKE '%-#{legacy_id}'"
    )

    if legacy_versions.empty?
      puts "No migration rows recorded under #{legacy_id}: nothing to adopt."
      next
    end

    adopted = 0
    dropped = 0

    legacy_versions.each do |version|
      number  = version.split('-').first
      target  = "#{number}-#{new_id}"
      exists  = connection.select_value(
        "SELECT 1 FROM #{sm_table} WHERE version = '#{target}' LIMIT 1"
      )

      if exists
        # Already migrated under the new id: drop the stale legacy row instead
        # of hitting the unique index on schema_migrations.version.
        connection.execute("DELETE FROM #{sm_table} WHERE version = '#{version}'")
        dropped += 1
      else
        connection.execute("UPDATE #{sm_table} SET version = '#{target}' WHERE version = '#{version}'")
        adopted += 1
      end
    end

    puts "Legacy rows found: #{legacy_versions.size} (adopted: #{adopted}, already migrated: #{dropped})"
    puts 'Run `rake redmine:plugins:migrate NAME=redmine_status_flow` to confirm (it should be a no-op).'
  end

  desc 'Rebuild status intervals in batches (PROJECT_ID=1 FORCE=1 BATCH_SIZE=500)'
  task rebuild: :environment do
    batch_size = (ENV['BATCH_SIZE'].presence || 500).to_i
    force      = ENV['FORCE'] == '1'
    project_id = ENV['PROJECT_ID'].presence

    scope = Issue.order(:id)
    scope = scope.where(project_id: project_id) if project_id

    total = scope.count
    puts "rebuild: #{total} issue(s), batch size #{batch_size}, force=#{force}"
    done = 0
    inserted = 0

    scope.find_in_batches(batch_size: batch_size) do |batch|
      ids = batch.map(&:id)
      existing = IssueStatusHistory.where(issue_id: ids).group(:issue_id).count
      targets = force ? ids : ids.reject { |id| existing[id].to_i.positive? }

      if force && targets.any?
        IssueStatusHistory.where(issue_id: targets).delete_all
      end

      inserted += RedmineStatusFlowTasks.rebuild_batch(targets) if targets.any?
      done += batch.size
      puts "rebuild: #{done}/#{total} issues scanned, #{inserted} interval(s) written"
    end

    puts "rebuild: done, #{inserted} interval(s) written"
  end

  desc 'Report orphan rows, missing history and stale last_status_update'
  task verify: :environment do
    orphans = RedmineStatusFlowTasks.orphan_scope.count
    no_history = Issue.where.not(id: IssueStatusHistory.select(:issue_id)).count
    stale = RedmineStatusFlowTasks.stale_scope.count
    problems = orphans + no_history + stale

    puts "orphan rows (journal deleted without callbacks): #{orphans}"
    puts "issues without any history row:                  #{no_history}"
    puts "issues with a stale last_status_update:          #{stale}"
    puts problems.zero? ? 'verify: clean' : "verify: #{problems} problem(s) found (see `prune`)"
    exit 1 if problems.positive?
  end

  desc 'Delete orphan rows and repair last_status_update (CONFIRM=1)'
  task prune: :environment do
    unless ENV['CONFIRM'] == '1'
      puts 'prune is destructive: re-run with CONFIRM=1 (back up the database first).'
      next
    end

    deleted = RedmineStatusFlowTasks.orphan_scope.delete_all
    puts "prune: #{deleted} orphan row(s) deleted"

    repaired = RedmineStatusFlowTasks.repair_last_status_update
    puts "prune: #{repaired} issue(s) with a repaired last_status_update"
  end
end
