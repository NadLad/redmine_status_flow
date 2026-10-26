class PopulateLastStatusUpdateIssues < ActiveRecord::Migration[6.1]
  # Same reasoning as 002: the per-issue loop (one UPDATE per issue over the
  # whole table) belongs in `rake redmine_status_flow:rebuild`, not inside the
  # migration transaction. Existing installations already ran this version.
  def up
    # no-op by design
  end

  def down
    Issue.update_all(last_status_update: nil) if column_exists?(:issues, :last_status_update)
  end
end
