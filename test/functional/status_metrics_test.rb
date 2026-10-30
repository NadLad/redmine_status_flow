# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The metrics page is the only place where a wrong number looks plausible: the
# table renders, the layout is fine, and the mean is quietly computed over the
# wrong rows. These tests pin the rendered values, not just the HTTP status.
class StatusMetricsTest < ActionController::TestCase
  tests StatusHistoriesController
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    Role.find(1).add_permission! :search_status_history
    @request.session[:user_id] = 2
    @project = Project.find(1)
    @issue = Issue.where(project_id: @project.id).visible(User.find(2)).first
    @base = Time.zone.parse('2026-08-01 09:00')
  end

  def interval(status_id:, days:)
    IssueStatusHistory.create!(issue: @issue, status_id: status_id, user_id: 2,
                               from: @base, to: @base + days.days)
  end

  def get_metrics(extra = {})
    get :metrics, params: { project_id: @project.identifier, date_from: '2026-08-01',
                            date_to: '2026-08-31' }.merge(extra)
  end

  test 'renders one row per status with the computed durations' do
    [1, 2, 3, 4].each { |days| interval(status_id: 1, days: days) }

    get_metrics

    assert_response :success
    assert_select 'table.status-flow-metrics tbody tr', 1
    assert_select 'td.count', text: '4'
    # mean and median of 1, 2, 3 and 4 days are both 2.5 days
    assert_select 'td', text: '2d 12h', count: 2
    # p90 and max are both the fourth day
    assert_select 'td', text: '4d 0h', count: 2
  end

  test 'offers the range form and the navigation' do
    get_metrics

    assert_response :success
    assert_select "form[action=?]", status_history_metrics_path(@project)
    assert_select 'input[name=date_from]'
    assert_select 'input[name=date_to]'
    assert_select "a[href=?]", search_status_history_path(@project)
  end

  test 'reports an invalid range instead of querying it' do
    interval(status_id: 1, days: 2)

    get_metrics(date_from: 'not-a-date')

    assert_response :success
    assert_equal I18n.t(:error_status_history_invalid_date), flash[:error]
    assert_select 'table.status-flow-metrics', count: 0
    assert_select 'p.nodata'
  end

  test 'shows the empty state for a range without intervals' do
    interval(status_id: 1, days: 2)

    get_metrics(date_from: '2020-01-01', date_to: '2020-01-31')

    assert_response :success
    assert_select 'table.status-flow-metrics', count: 0
    assert_select 'p.nodata'
  end

  test 'requires the project permission' do
    Role.find(1).remove_permission! :search_status_history

    get_metrics

    assert_response :forbidden
  end
end
