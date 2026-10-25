module RedmineStatusHistory
  module Patches
    module IssuePatch
      def self.included(base)
        base.send(:include, InstanceMethods)
        base.class_eval do
          has_many :issue_status_histories, -> { order(:from, :id) }, dependent: :delete_all

          before_create :set_default_last_status_update
          after_create :create_status_history
        end
      end

      module InstanceMethods
        # Opens the first interval of the issue's timeline.
        #
        # Same rule as JournalDetailPatch: a failure here must not abort the
        # issue creation the user actually asked for, so the insert runs in a
        # savepoint and failures are logged instead of raised.
        def create_status_history
          IssueStatusHistory.transaction(requires_new: true) do
            IssueStatusHistory.create!(
              from: created_on || Time.current,
              status_id: status_id,
              user_id: author_id,
              issue_id: id
            )
          end
        rescue StandardError => e
          Rails.logger.warn(
            "[redmine_status_flow] no initial history row for issue #{id}: #{e.class}: #{e.message}"
          )
          nil
        end

        def set_default_last_status_update
          self.last_status_update = Time.current
        end
      end
    end
  end
end
