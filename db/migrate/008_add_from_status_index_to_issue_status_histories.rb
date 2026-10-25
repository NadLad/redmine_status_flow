class AddFromStatusIndexToIssueStatusHistories < ActiveRecord::Migration[6.1]
  INDEX_NAME = 'index_status_histories_on_from_and_status'.freeze

  def up
    return if index_exists?(:issue_status_histories, %i[from status_id], name: INDEX_NAME)

    # The transition search filters on a `from` range and optionally a status.
    # Existing indexes lead with status_id or issue_id, so neither serves it.
    add_index :issue_status_histories, %i[from status_id], name: INDEX_NAME
  end

  def down
    remove_index :issue_status_histories, name: INDEX_NAME if index_exists?(:issue_status_histories, %i[from status_id], name: INDEX_NAME)
  end
end
