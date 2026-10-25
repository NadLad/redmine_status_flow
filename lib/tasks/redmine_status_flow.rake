# Rake tasks for the Redmine Status Flow plugin.
#
# Plugin migrations are tracked in the shared `schema_migrations` table under
# "<version>-<plugin_id>". Renaming the plugin id (redmine_status_history ->
# redmine_status_flow) therefore hides the already-applied migrations from
# Redmine, which would replay them on the next `redmine:plugins:migrate`.
# `adopt_legacy_identity` rewrites those rows so an existing installation
# upgrading from upstream keeps its migration state.
namespace :redmine_status_flow do
  desc 'Adopt migration rows recorded under the legacy redmine_status_history plugin id'
  task adopt_legacy_identity: :environment do
    legacy_id = 'redmine_status_history'
    new_id    = 'redmine_status_flow'

    sm_table = ActiveRecord::Base.connection.pool.schema_migration.table_name
    rows = ActiveRecord::Base.connection.select_values(
      "SELECT version FROM #{sm_table} WHERE version LIKE '%-#{legacy_id}'"
    )

    if rows.empty?
      puts "No migration rows recorded under #{legacy_id}: nothing to adopt."
      next
    end

    rows.each do |version|
      number = version.split('-').first
      ActiveRecord::Base.connection.execute(
        "UPDATE #{sm_table} SET version = '#{number}-#{new_id}' WHERE version = '#{version}'"
      )
    end

    puts "Adopted #{rows.size} migration row(s): #{rows.join(', ')} -> #{new_id}"
    puts 'Run `rake redmine:plugins:migrate NAME=redmine_status_flow` to confirm (it should be a no-op).'
  end
end
