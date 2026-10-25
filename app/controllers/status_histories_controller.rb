class StatusHistoriesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def search
    @statuses = @project.trackers.flat_map(&:issue_statuses).uniq.sort_by(&:name)
    @status_to = params[:status_to]
    @date_from = params[:date_from].presence || (request.get? ? User.current.today.iso8601 : nil)
    @status_from = params[:status_from].presence
    @date_to = params[:date_to].presence

    @issues = []

    return unless request.post?

    from = parse_date(@date_from)
    to = parse_date(@date_to) if @date_to.present?
    unless from && (@date_to.blank? || to)
      flash.now[:error] = l(:error_status_history_invalid_date)
      return
    end
    if to && to < from
      flash.now[:error] = l(:error_status_history_invalid_date)
      return
    end

    @issues = IssueStatusHistory.search_changes(@project, @status_to, from, @status_from, to, User.current)
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
