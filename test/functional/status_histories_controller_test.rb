# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class StatusHistoriesControllerTest < ActionController::TestCase
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    Role.find(1).add_permission! :search_status_history
    @request.session[:user_id] = 2
    @project = Project.find(1)
  end

  test 'shows the search form to an authorized member' do
    get :search, params: { project_id: @project.identifier }

    assert_response :success
    assert_select 'form[action=?]', search_status_history_path(@project)
  end

  test 'requires the project permission' do
    Role.find(1).remove_permission! :search_status_history

    get :search, params: { project_id: @project.identifier }

    assert_response :forbidden
  end

  test 'reports an invalid date without running a search' do
    post :search, params: { project_id: @project.identifier, date_from: 'not-a-date', status_to: 1 }

    assert_response :success
    assert_equal I18n.t(:error_status_history_invalid_date), flash[:error]
    assert_select 'table.issues', count: 0
    assert_select 'p.nodata'
  end

  test 'searches status changes' do
    issue = Issue.find(1)
    IssueStatusHistory.create!(issue: issue, status_id: 2, previous_status_id: 1,
                               user: User.find(2), from: Time.zone.parse('2026-08-03 12:00'))

    post :search, params: { project_id: @project.identifier, date_from: '2026-08-03',
                            date_to: '2026-08-03', status_from: 1, status_to: 2 }

    assert_response :success
    assert_select "tr#issue-#{issue.id}", count: 1
  end
end
