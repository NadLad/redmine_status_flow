# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The timeline used to be rendered by a remote link into #ajax-modal. It is now
# part of the issue page itself, through view_issues_show_details_bottom, so
# these tests go through the full stack (routing, hook, helper, partial, i18n)
# instead of calling a controller action directly.
class IssueTimelineTest < Redmine::IntegrationTest
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    @issue = Issue.find(1)
    log_user('jsmith', 'jsmith')
  end

  def seed_timeline(issue)
    issue.issue_status_histories.create!(
      from: issue.created_on,
      to: issue.created_on + 1.day,
      status_id: 1,
      user_id: issue.author_id
    )
    issue.issue_status_histories.create!(
      from: issue.created_on + 1.day,
      status_id: 2,
      previous_status_id: 1,
      user_id: issue.author_id
    )
  end

  test 'renders the timeline inline on the issue page' do
    seed_timeline(@issue)

    get "/issues/#{@issue.id}"

    assert_response :success
    assert_select '#issue-status-flow', 1
    assert_select '#issue-status-flow ol.status-flow-list li.status-flow-item', 2
    assert_select '#issue-status-flow li.status-flow-current', 1
    assert_match(/1d/, response.body)
  end

  test 'the timeline is inside the attributes block, not a modal' do
    seed_timeline(@issue)

    get "/issues/#{@issue.id}"

    assert_response :success
    assert_select 'div.attributes #issue-status-flow', 1
    # #ajax-modal is part of Redmine's own layout (other features use it), so
    # what matters is that nothing in it points at a history request anymore.
    assert_select 'a[data-remote][href*=issue_status_history]', 0
  end

  test 'links the plugin stylesheet' do
    seed_timeline(@issue)

    get "/issues/#{@issue.id}"

    assert_response :success
    assert_select 'link[rel=stylesheet][href*=redmine_status_flow]', 1
  end

  test 'renders nothing when the issue has no history row' do
    get "/issues/#{@issue.id}"

    assert_response :success
    assert_select '#issue-status-flow', 0
  end

  test 'the legacy modal endpoint is gone' do
    seed_timeline(@issue)

    get "/projects/#{@issue.project.identifier}/issue_status_history/#{@issue.id}"

    assert_response :missing
  end
end
