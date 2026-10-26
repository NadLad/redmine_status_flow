class StatusHistoriesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def search
    @statuses = @project.trackers.flat_map(&:issue_statuses).uniq.sort_by(&:name)
    @status_to = params[:status_to]
    @date_from = params[:date_from].presence || (submitted? ? nil : User.current.today.iso8601)
    @status_from = params[:status_from].presence
    @date_to = params[:date_to].presence

    @issues = []
    @issue_count = 0

    return unless submitted?

    from = parse_date(@date_from)
    to = parse_date(@date_to) if @date_to.present?
    if from.nil? || (@date_to.present? && to.nil?)
      flash.now[:error] = l(:error_status_history_invalid_date)
      return
    end
    if to && to < from
      flash.now[:error] = l(:error_status_history_invalid_date)
      return
    end

    scope = IssueStatusHistory.search_changes(@project, @status_to, from, @status_from, to, User.current)
    paginate(scope)
  end

  private

  # The results are paginated, so the page has to survive a reload: the form
  # submits with GET and carries this marker. POST is still accepted for links
  # and forms created before the switch.
  def submitted?
    request.post? || params[:search].present?
  end

  # per_page_option is ApplicationController's own helper: it honours
  # ?per_page=, remembers the choice in the session and falls back to
  # Setting.per_page_options.
  def paginate(scope)
    per_page = per_page_option
    @issue_count = scope.count
    @issue_pages = Redmine::Pagination::Paginator.new(@issue_count, per_page, params[:page])
    @issues = scope.limit(per_page).offset(@issue_pages.offset).to_a
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end
end
