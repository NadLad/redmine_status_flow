# frozen_string_literal: true

module RedmineStatusHistory
  # Aggregates how long issues stayed in each status over a project and a date
  # range.
  #
  # Percentiles are computed in Ruby on purpose: SQLite -- the database the CI
  # matrix runs on -- has no `percentile_cont`, and a per-adapter SQL branch
  # would mean three implementations to keep in sync for a report that already
  # works on a bounded date range. The trade-off is memory: one Float per
  # interval, plucked straight from the table (no model instantiation, no
  # association loading).
  class Metrics
    # `p90` uses the nearest-rank definition: the smallest observed duration
    # that is at or above the 90th percentile of the sorted values, i.e.
    # element ceil(0.9 * n). The median averages the two middle values when the
    # count is even. Both are stated here because "p90" has at least three
    # definitions in the wild and a report is worthless if the reader cannot
    # tell which one produced the number.
    Row = Struct.new(:status, :count, :total, :mean, :median, :p90, :max, keyword_init: true) do
      def status_label
        status.respond_to?(:name) ? status.name : status.to_s
      end

      def mean_label
        IssueStatusHistory.format_duration(mean)
      end

      def median_label
        IssueStatusHistory.format_duration(median)
      end

      def p90_label
        IssueStatusHistory.format_duration(p90)
      end

      def max_label
        IssueStatusHistory.format_duration(max)
      end

      def total_label
        IssueStatusHistory.format_duration(total)
      end
    end

    # Intervals whose start falls inside the range, on issues the user may see
    # in that project. Same visibility rule as the search and the export, so a
    # report never leaks a count from a project the user cannot read.
    def self.scope(project, from, to, user = User.current)
      visible = Issue.where(project_id: project.id).visible(user).select(:id)

      IssueStatusHistory
        .where(issue_id: visible)
        .where(from: from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day)
    end

    def self.report(project, from:, to:, user: User.current, now: Time.current)
      new(scope(project, from, to, user), now: now).rows
    end

    def initialize(scope, now: Time.current)
      @scope = scope
      @now = now
    end

    # Slowest status first: the report exists to surface the status that eats
    # the time, not to list statuses in id order.
    def rows
      durations = Hash.new { |hash, key| hash[key] = [] }

      @scope.pluck(:status_id, :from, :to).each do |status_id, from, to|
        next unless from

        # A negative duration means clock skew between the journal timestamp
        # and the interval; clamping keeps it from dragging a mean below zero.
        durations[status_id] << [((to || @now) - from), 0].max
      end

      statuses = IssueStatus.all.index_by(&:id)
      durations.map { |status_id, values| build_row(statuses[status_id], status_id, values) }
               .sort_by { |row| -row.mean }
    end

    private

    def build_row(status, status_id, values)
      sorted = values.sort
      total = sorted.sum

      Row.new(status: status || status_id.to_s,
              count: sorted.size,
              total: total,
              mean: total.to_f / sorted.size,
              median: median(sorted),
              p90: percentile(sorted, 0.9),
              max: sorted.last)
    end

    def median(sorted)
      middle = sorted.size / 2
      return sorted[middle].to_f if sorted.size.odd?

      (sorted[middle - 1] + sorted[middle]) / 2.0
    end

    def percentile(sorted, quantile)
      rank = (quantile * sorted.size).ceil
      sorted[(rank - 1).clamp(0, sorted.size - 1)]
    end
  end
end
