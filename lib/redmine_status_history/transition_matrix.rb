# frozen_string_literal: true

module RedmineStatusHistory
  # Counts how often work moved from one status to another over a project and a
  # date range, as a from -> to matrix.
  #
  # The diagram is rendered server-side on purpose. Redmine 7 bundles Chart.js
  # 4.5.1, whose core has no Sankey controller (that lives in a separate
  # package), and the plugin ships no JavaScript at all so the same code runs
  # on Redmine 5.1, which has no importmap. A table with heat classes needs
  # neither.
  class TransitionMatrix
    # Transitions whose new status started in the range. The creation row has
    # no previous status: it is an origin, not a transition, and including it
    # would add a phantom column.
    def self.scope(project, from, to, user = User.current)
      visible = Issue.where(project_id: project.id).visible(user).select(:id)

      IssueStatusHistory
        .where(issue_id: visible)
        .where.not(previous_status_id: nil)
        .where(from: from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day)
    end

    def self.report(project, from:, to:, user: User.current)
      new(scope(project, from, to, user).group(:previous_status_id, :status_id).count)
    end

    def initialize(counts)
      @counts = counts
    end

    def empty?
      @counts.empty?
    end

    # Rows and columns are the same list, sorted by name so the matrix reads
    # like the status list an administrator configured, not like id order.
    def statuses
      @statuses ||= @counts.keys.flatten.uniq
                          .filter_map { |id| IssueStatus.find_by(id: id) }
                          .sort_by { |status| status.name.to_s.downcase }
    end

    def total
      @counts.values.sum
    end

    def row_total(status)
      @counts.sum { |(from_id, _), count| from_id == status.id ? count : 0 }
    end

    def column_total(status)
      @counts.sum { |(_, to_id), count| to_id == status.id ? count : 0 }
    end

    def cell(from_status, to_status)
      @counts.fetch([from_status.id, to_status.id], 0)
    end

    # Share of the row, so a busy status does not look like a frequent
    # transition just because it receives more work.
    def share(from_status, to_status)
      row = row_total(from_status)
      return 0.0 if row.zero?

      cell(from_status, to_status).to_f / row
    end

    # CSS heat bucket: 1 (rare for its row) through 5 (the whole row). Zero
    # cells get no class at all, so the table stays readable.
    def heat(from_status, to_status)
      return 0 if cell(from_status, to_status).zero?

      (share(from_status, to_status) * 5).ceil.clamp(1, 5)
    end
  end
end
