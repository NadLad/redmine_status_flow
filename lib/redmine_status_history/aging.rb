# frozen_string_literal: true

module RedmineStatusHistory
  # Lists the issues that have been sitting in their current status for a while
  # and flags the ones past their threshold.
  #
  # Thresholds live in the plugin settings, keyed by status name, because the
  # status ids differ between installations while the names are what an
  # administrator reads in the settings form. A status without its own line
  # falls back to the default, so adding a status never silently drops out of
  # the report.
  class Aging
    DEFAULT_DAYS = 7

    Entry = Struct.new(:interval, :days, :threshold, :over, keyword_init: true) do
      def issue
        interval.issue
      end

      def status
        interval.status
      end

      def over?
        over
      end
    end

    def self.settings
      Setting.plugin_redmine_status_flow || {}
    end

    def self.default_days
      days = settings['aging_default_days'].to_i
      days.positive? ? days : DEFAULT_DAYS
    end

    # One "Status name: days" (or "Status name = days") per line. Anything that
    # does not parse is ignored on purpose: a typo in the settings must not
    # blank the whole report, it should leave that status on the default.
    def self.thresholds
      settings['aging_thresholds'].to_s.each_line.each_with_object({}) do |line, map|
        match = line.match(/\A\s*(.+?)\s*[=:]\s*(\d+)\s*\z/)
        map[match[1].downcase] = match[2].to_i if match
      end
    end

    # Open intervals on issues the user may see. Closed statuses are excluded:
    # an issue resting in "Closed" for a year is not stuck, and listing it would
    # bury the ones that are.
    def self.scope(project, user = User.current)
      visible = Issue.where(project_id: project.id).visible(user).select(:id)
      closed_statuses = IssueStatus.where(is_closed: true).select(:id)

      IssueStatusHistory
        .where(issue_id: visible, to: nil)
        .where.not(status_id: closed_statuses)
        .includes(:status, issue: %i[tracker assigned_to])
        .order(:from)
    end

    def self.report(project, user: User.current, now: Time.current)
      thresholds = self.thresholds
      fallback = default_days

      scope(project, user).map do |interval|
        threshold = thresholds[interval.status&.name.to_s.downcase] || fallback

        # Full days elapsed: an issue becomes "over" once it has spent at
        # least `threshold` complete days in the status, which is how an SLA
        # reads ("7 days to pick it up").
        days = ((now - interval.from) / 86_400).floor

        Entry.new(interval: interval, days: days, threshold: threshold, over: days >= threshold)
      end
    end
  end
end
