# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The aging page is a sorted list with a filter and a threshold, so the tests
# pin the order and the flag, not just the HTTP status. ?sort= is also an
# injection surface: it goes through an allow-list, and one test keeps it that
# way.
class StatusAgingTest < ActionController::TestCase
  tests StatusHistoriesController
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    Role.find(1).add_permission! :search_status_history
    @request.session[:user_id] = 2
    @project = Project.find(1)
    @issues = Issue.where(project_id: @project.id).visible(User.find(2)).limit(5).to_a
    @now = Time.zone.now
    Setting.plugin_redmine_status_flow = { 'aging_default_days' => '7', 'aging_thresholds' => 'Assigned: 2' }
  end

  def open_interval(issue:, status_id:, days_ago:)
    IssueStatusHistory.create!(issue: issue, status_id: status_id, user_id: 2,
                               from: @now - days_ago.days, to: nil)
  end

  def rows
    css_select('table.status-flow-aging tbody tr').map { |tr| tr['id'] }
  end

  test 'lists open issues with their days, threshold and flag' do
    slow = @issues[0]
    fast = @issues[1]
    open_interval(issue: slow, status_id: 1, days_ago: 10)
    open_interval(issue: fast, status_id: 1, days_ago: 3)

    get :aging, params: { project_id: @project.identifier }

    assert_response :success
    assert_select 'table.status-flow-aging tbody tr', 2
    assert_select "tr#issue-#{slow.id}.status-flow-aging-over", 1
    assert_select "tr#issue-#{fast.id}.status-flow-aging-over", 0
    assert_select "tr#issue-#{slow.id} td.days", text: '10'
    assert_select "tr#issue-#{slow.id} td.threshold", text: '7'
    assert_select 'span.status-flow-aging-flag', 1
    assert_select 'p.status-flow-report-summary', 1
  end

  test 'filters to the issues over their threshold' do
    slow = @issues[0]
    fast = @issues[1]
    open_interval(issue: slow, status_id: 1, days_ago: 10)
    open_interval(issue: fast, status_id: 1, days_ago: 3)

    get :aging, params: { project_id: @project.identifier, over: 1 }

    assert_response :success
    assert_equal ["issue-#{slow.id}"], rows
  end

  test 'sorts by days ascending when asked' do
    slow = @issues[0]
    fast = @issues[1]
    open_interval(issue: slow, status_id: 1, days_ago: 10)
    open_interval(issue: fast, status_id: 1, days_ago: 3)

    get :aging, params: { project_id: @project.identifier, sort: 'days', direction: 'asc' }

    assert_response :success
    assert_equal ["issue-#{fast.id}", "issue-#{slow.id}"], rows
  end

  test 'ignores a sort column outside the allow-list' do
    slow = @issues[0]
    fast = @issues[1]
    open_interval(issue: slow, status_id: 1, days_ago: 10)
    open_interval(issue: fast, status_id: 1, days_ago: 3)

    get :aging, params: { project_id: @project.identifier, sort: 'issues.id DESC' }

    assert_response :success
    # Unknown column falls back to the default sort, days descending: the
    # oldest interval first. A valid ?direction= is still honoured; only the
    # column is discarded.
    assert_equal ["issue-#{slow.id}", "issue-#{fast.id}"], rows
  end

  test 'shows the empty state without open intervals' do
    get :aging, params: { project_id: @project.identifier }

    assert_response :success
    assert_select 'table.status-flow-aging', count: 0
    assert_select 'p.nodata'
  end

  test 'requires the project permission' do
    Role.find(1).remove_permission! :search_status_history
    open_interval(issue: @issues[0], status_id: 1, days_ago: 10)

    get :aging, params: { project_id: @project.identifier }

    assert_response :forbidden
  end
end
