class IssueStatusHistory < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  belongs_to :status, class_name: 'IssueStatus'
  belongs_to :previous_status, class_name: 'IssueStatus', optional: true
  belongs_to :user
  belongs_to :journal, optional: true
  belongs_to :issue

  after_create :update_last_status_update

  scope :chronological, -> { order(:from, :id) }

  # Above this many intervals the inline timeline starts collapsed, so a
  # fifty-change history does not push the issue description off the screen.
  TIMELINE_AUTO_OPEN = 8

  # Associations the search results actually render. Preloading them keeps the
  # query count flat: without it, every row fires its own tracker/status/
  # assigned_to/project query from the view.
  SEARCH_PRELOAD = %i[project tracker status priority assigned_to author].freeze

  # Associations the CSV/PDF export renders. The interval's own columns plus
  # the issue's tracker, so the export stays N+1-free like the search.
  INTERVAL_PRELOAD = [{ issue: :tracker }, :status, :previous_status, :user].freeze

  def self.search_changes(project, status_id, date_from, previous_status_id = nil, date_to = nil,
                          user = User.current)
    conditions = interval_conditions(status_id, date_from, previous_status_id, date_to)

    Issue
      .where(project_id: project.id)
      .visible(user)
      .joins(:issue_status_histories)
      .where({ issue_status_histories: conditions })
      .distinct
      .preload(*SEARCH_PRELOAD)
  end

  # The export is the history itself (one row per interval), not the distinct
  # issues the search page lists. Same filters and visibility as
  # `search_changes`, but on the interval table and preloaded for rendering.
  def self.search_intervals(project, status_id, date_from, previous_status_id = nil, date_to = nil,
                            user = User.current)
    conditions = interval_conditions(status_id, date_from, previous_status_id, date_to)
    visible_issue_ids = Issue.where(project_id: project.id).visible(user).select(:id)

    IssueStatusHistory
      .where(issue_id: visible_issue_ids)
      .where(conditions)
      .order(:from, :id)
      .preload(*INTERVAL_PRELOAD)
  end

  class << self
    private

    def interval_conditions(status_id, date_from, previous_status_id, date_to)
      start_at = date_from.in_time_zone.beginning_of_day
      end_at = (date_to || Time.zone.today).in_time_zone.end_of_day
      conditions = { from: start_at..end_at }

      conditions[:status_id] = status_id if status_id.present?

      conditions[:previous_status_id] = previous_status_id if previous_status_id.present?

      conditions
    end
  end

  def update_last_status_update
    return unless issue && from
    return if issue.last_status_update && issue.last_status_update > from

    issue.update_column(:last_status_update, from)
  end

  def lifetime
    (to || Time.current) - from
  end

  def lifetime_in_minutes
    lifetime / 60.0
  end

  # The interval that is still running: the issue's current status.
  def open?
    to.nil?
  end

  # Compact, locale-aware duration: "3d 4h", "4h 12min", "12min", "< 1min".
  #
  # This lives on the model rather than in a view helper because Redmine runs
  # with `include_all_helpers = false` and a plugin is not an engine, so a
  # plugin's app/helpers module is never mixed into another controller's views
  # -- which is exactly where a view hook renders. Keeping it here means the
  # partial needs no plugin helper to work.
  def duration_label
    self.class.format_duration(lifetime)
  end

  # Formats a raw number of seconds with the same rules as an interval's own
  # label. The reports aggregate durations that no longer belong to a single
  # interval (a mean, a p90), so the formatting has to live somewhere both the
  # model and the metrics report can call.
  def self.format_duration(seconds)
    seconds = seconds.to_i
    return I18n.t(:label_status_flow_under_minute) if seconds < 60

    days, rest = seconds.divmod(86_400)
    hours, rest = rest.divmod(3_600)
    minutes = rest / 60

    if days.positive?
      I18n.t(:label_status_flow_duration_days, days: days, hours: hours)
    elsif hours.positive?
      I18n.t(:label_status_flow_duration_hours, hours: hours, minutes: minutes)
    else
      I18n.t(:label_status_flow_duration_minutes, minutes: minutes)
    end
  end
end
