# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The matrix page is checked at the DOM level: the heat class is what carries
# the reading, so a cell with the right number and the wrong bucket is still a
# broken report.
class StatusTransitionsTest < ActionController::TestCase
  tests StatusHistoriesController
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    Role.find(1).add_permission! :search_status_history
    @request.session[:user_id] = 2
    @project = Project.find(1)
    @issues = Issue.where(project_id: @project.id).visible(User.find(2)).limit(8).to_a
    @base = Time.zone.parse('2026-08-10 09:00')
  end

  def transition(from_status:, to_status:, issue: nil)
    IssueStatusHistory.create!(issue: issue || @issues.shift, status_id: to_status,
                               previous_status_id: from_status, user_id: 2,
                               from: @base, to: @base + 1.day)
  end

  def get_matrix(extra = {})
    get :transitions, params: { project_id: @project.identifier, date_from: '2026-08-01',
                                date_to: '2026-08-31' }.merge(extra)
  end

  def seed_matrix
    3.times { transition(from_status: 1, to_status: 2) }
    transition(from_status: 1, to_status: 3)
    2.times { transition(from_status: 2, to_status: 3) }
  end

  test 'renders counts, row shares and heat buckets' do
    seed_matrix

    get_matrix

    assert_response :success
    assert_select 'table.status-flow-matrix', 1
    assert_select 'tr#row-1 td.heat-4', count: 1
    assert_select 'tr#row-1 td.heat-4 span.share', text: '75%'
    assert_select 'tr#row-1 td.heat-2 span.share', text: '25%'
    assert_select 'tr#row-2 td.heat-5 span.share', text: '100%'
    assert_select 'tr#row-1 td.row-total', text: '4'
    assert_select 'tfoot th', text: '6'
  end

  test 'offers the range form and the navigation' do
    get_matrix

    assert_response :success
    assert_select "form[action=?]", status_history_transitions_path(@project)
    assert_select 'input[name=date_from]'
    assert_select 'input[name=date_to]'
    assert_select "a[href=?]", status_history_metrics_path(@project)
    assert_select "a[href=?]", status_history_aging_path(@project)
  end

  test 'shows the empty state without transitions' do
    get_matrix

    assert_response :success
    assert_select 'table.status-flow-matrix', count: 0
    assert_select 'p.nodata'
  end

  test 'reports an invalid range instead of querying it' do
    seed_matrix

    get_matrix(date_to: 'not-a-date')

    assert_response :success
    assert_equal I18n.t(:error_status_history_invalid_date), flash[:error]
    assert_select 'table.status-flow-matrix', count: 0
  end

  test 'requires the project permission' do
    Role.find(1).remove_permission! :search_status_history
    seed_matrix

    get_matrix

    assert_response :forbidden
  end
end
