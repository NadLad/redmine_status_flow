module RedmineStatusHistory
  module Patches
    module JournalDetailPatch
      def self.included(base) # :nodoc:
        base.send(:include, InstanceMethods)
        base.class_eval do
          after_create :create_history
        end
      end

      module InstanceMethods
        # Records the status interval opened by this journal detail.
        #
        # This runs inside the issue update's transaction, so anything raised
        # here aborts the user's edit. A history row is secondary data: when it
        # cannot be written we log and move on instead of returning a 500.
        # The insert runs in a savepoint (requires_new) so a failed statement
        # does not poison the surrounding transaction on PostgreSQL.
        def create_history
          return unless prop_key == 'status_id'
          return unless journal&.journalized.is_a?(Issue)
          return if IssueStatusHistory.exists?(journal_id: journal_id)

          issue = journal.journalized
          changed_at = journal.created_on || Time.current

          IssueStatusHistory.transaction(requires_new: true) do
            last_change = issue.issue_status_histories.chronological.last
            IssueStatusHistory.create!(
              from: changed_at,
              status_id: value,
              user_id: journal.user_id,
              journal_id: journal_id,
              previous_status_id: old_value,
              issue_id: issue.id
            )
            last_change&.update!(to: changed_at)
          end
        rescue ActiveRecord::RecordNotUnique
          # The unique index on journal_id caught a concurrent insert for the
          # same journal: the row already exists, nothing to do.
          nil
        rescue StandardError => e
          Rails.logger.warn(
            "[redmine_status_flow] no history row for journal_detail #{id} " \
            "(journal #{journal_id}): #{e.class}: #{e.message}"
          )
          nil
        end
      end
    end
  end
end
