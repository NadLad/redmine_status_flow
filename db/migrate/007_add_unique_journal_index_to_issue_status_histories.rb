class AddUniqueJournalIndexToIssueStatusHistories < ActiveRecord::Migration[6.1]
  INDEX_NAME = 'index_status_histories_on_journal_id_unique'.freeze

  def up
    deduplicate_journal_rows
    return if index_exists?(:issue_status_histories, :journal_id, name: INDEX_NAME)

    # A journal detail produces at most one interval. The model-level guard
    # (exists?) is a race; the unique index is what actually enforces it.
    # NULL journal_id rows are unaffected: no mainstream engine treats two
    # NULLs as equal in a unique index.
    add_index :issue_status_histories, :journal_id, unique: true, name: INDEX_NAME

    # 006 added a plain index on the same column; the unique one covers it.
    legacy_index = 'index_issue_status_histories_on_journal_id'
    remove_index :issue_status_histories, name: legacy_index if index_exists?(:issue_status_histories, :journal_id, name: legacy_index)
  end

  def down
    remove_index :issue_status_histories, name: INDEX_NAME if index_exists?(:issue_status_histories, :journal_id, name: INDEX_NAME)
    add_index :issue_status_histories, :journal_id unless index_exists?(:issue_status_histories, :journal_id, name: 'index_issue_status_histories_on_journal_id')
  end

  private

  # Existing installations may hold duplicates created before the index
  # existed. Keep the oldest row of each journal_id so the index can be added.
  def deduplicate_journal_rows
    return unless table_exists?(:issue_status_histories)

    execute <<~SQL
      DELETE FROM issue_status_histories
      WHERE journal_id IS NOT NULL
        AND id NOT IN (
          SELECT keep_id FROM (
            SELECT MIN(id) AS keep_id
            FROM issue_status_histories
            WHERE journal_id IS NOT NULL
            GROUP BY journal_id
          ) AS survivors
        )
    SQL
  end
end
