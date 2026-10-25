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

  def self.search_changes(project, status_id, date_from, previous_status_id = nil, date_to = nil,
                          user = User.current)
    start_at = date_from.in_time_zone.beginning_of_day
    end_at = (date_to || Time.zone.today).in_time_zone.end_of_day
    conditions = {
      from: start_at..end_at
    }

    conditions[:status_id] = status_id if status_id.present?

    conditions[:previous_status_id] = previous_status_id if previous_status_id.present?

    Issue
      .where(project_id: project.id)
      .visible(user)
      .joins(:issue_status_histories)
      .where({ issue_status_histories: conditions })
      .distinct
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
    seconds = lifetime.to_i
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
