# Rake tasks for the Redmine Status Flow plugin.
#
# Plugin migrations are tracked in the shared `schema_migrations` table under
# "<version>-<plugin_id>". Renaming the plugin id (redmine_status_history ->
# redmine_status_flow) therefore hides already-applied migrations from
# Redmine, which would replay them on the next `redmine:plugins:migrate`.
# `adopt_legacy_identity` rewrites those rows so an existing installation
# upgrading from upstream keeps its migration state.
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
end
