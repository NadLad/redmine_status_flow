class StatusHistoriesController < ApplicationController
  include RedmineStatusHistory::Export

  before_action :find_project_by_project_id, only: :search
  before_action :find_issue_project, only: :issue_export
  before_action :authorize

  def search
    @statuses = @project.trackers.flat_map(&:issue_statuses).uniq.sort_by(&:name)
    @status_to = params[:status_to]
    @date_from = params[:date_from].presence || (submitted? ? nil : User.current.today.iso8601)
    @status_from = params[:status_from].presence
    @date_to = params[:date_to].presence

    @issues = []
    @issue_count = 0

    respond_to do |format|
      format.html { search_html }
      format.csv  { search_export(:csv) }
      format.pdf  { search_export(:pdf) }
    end
  end

  # Exports the history of a single issue. The timeline on the issue page
  # links here; authorization is the project's :search_status_history
  # permission, the same one that guards the transition search.
  def issue_export
    intervals = @issue.issue_status_histories.includes(:status, :previous_status, :user).chronological

    respond_to do |format|
      format.csv do
        send_data history_to_csv(intervals),
                  type: 'text/csv; header=present',
                  filename: "issue_#{@issue.id}_status_history.csv"
      end
      format.pdf do
        send_data history_to_pdf(intervals, @project),
                  type: 'application/pdf',
                  filename: "issue_#{@issue.id}_status_history.pdf"
      end
    end
  end

  private

  # The export links always carry `search=1`, so a direct .csv/.pdf request
  # without it returns an empty but valid document rather than a 500. An
  # invalid range does the same: the HTML form already reports the error, the
  # export just refuses to run a query with bad bounds.
  def search_export(format)
    from, to, invalid = search_range
    intervals =
      if submitted? && !invalid
        IssueStatusHistory.search_intervals(@project, @status_to, from, @status_from, to, User.current)
      else
        IssueStatusHistory.none
      end

    if format == :csv
      send_data history_to_csv(intervals),
                type: 'text/csv; header=present',
                filename: 'status_history.csv'
    else
      send_data history_to_pdf(intervals, @project),
                type: 'application/pdf',
                filename: 'status_history.pdf'
    end
  end

  def search_html
    return unless submitted?

    from, to, invalid = search_range
    if invalid
      flash.now[:error] = l(:error_status_history_invalid_date)
      return
    end

    scope = IssueStatusHistory.search_changes(@project, @status_to, from, @status_from, to, User.current)
    paginate(scope)
  end

  def search_range
    from = parse_date(@date_from)
    to = parse_date(@date_to) if @date_to.present?
    invalid = from.nil? || (@date_to.present? && to.nil?) || (to && to < from)
    [from, to, invalid]
  end

  def find_issue_project
    @issue = Issue.visible.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

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
