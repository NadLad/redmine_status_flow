class PopulateIssueStatusHistory < ActiveRecord::Migration[6.1]
  # The backfill used to run here: Issue.find_each with N+1 journal loading,
  # inside the migration's single transaction. On a large installation that is
  # hours of table lock, and a failure halfway could not be resumed.
  #
  # It now lives in `rake redmine_status_flow:rebuild` (batched, resumable,
  # idempotent). Existing installations already ran this version, so their
  # migration state is unchanged; fresh installs run rebuild after migrating.
  def up
    # no-op by design
  end

  def down
    execute 'DELETE FROM issue_status_histories' if table_exists?(:issue_status_histories)
  end
end
