# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The search page lists issues through the history table. Two things are
# checked here that a controller unit test cannot see: that the rendered page
# does not fire one query per row, and that the result set is paginated.
class StatusSearchTest < Redmine::IntegrationTest
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    Role.find(1).add_permission! :search_status_history
    log_user('jsmith', 'jsmith')
    @project = Project.find(1)
  end

  def search_path(extra = {})
    "/projects/#{@project.identifier}/issue_status_history/search?" +
      { search: 1, status_to: 2, date_from: 10.years.ago.to_date.to_s }.merge(extra).to_query
  end

  # Only issues of the project under search, and only ones jsmith can see:
  # seeding from Issue.limit would pull rows from other projects and make the
  # expected row count depend on the fixtures.
  def seed(count)
    Issue.where(project_id: @project.id).visible(User.find(2)).limit(count).each do |issue|
      IssueStatusHistory.create!(issue: issue, status_id: 2, previous_status_id: 1,
                                 user_id: 2, from: 2.days.ago)
    end
  end

  # Only the SELECTs: the request also writes session/Setting rows, and those
  # do not vary with the number of results.
  def select_count
    count = 0
    callback = lambda do |*, payload|
      count += 1 unless payload[:cached] || payload[:name] == 'SCHEMA'
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { yield }
    count
  end

  test 'the search form submits with GET so a page can be linked and reloaded' do
    get search_path

    assert_response :success
    assert_select 'form[method=get]'
    assert_select 'input[type=hidden][name=search]'
  end

  test 'the page renders without a per-row query' do
    seed(1)
    get search_path
    one = select_count { get search_path }

    IssueStatusHistory.delete_all
    seeded = seed(8).size
    get search_path
    many = select_count { get search_path }

    assert_response :success
    assert_operator seeded, :>=, 2, 'not enough issues in the fixture project to compare'
    assert_select 'table.issues tbody tr', seeded
    assert_operator many - one, :<=, 3,
                    "query count grew with the result set (#{one} -> #{many}): an N+1 is back"
  end

  test 'results are paginated' do
    # per_page_option only accepts values listed in Setting.per_page_options.
    Setting.per_page_options = '3'
    seeded = seed(8).size

    get search_path(per_page: 3)

    assert_response :success
    assert_select 'span.pagination'
    assert_select 'table.issues tbody tr', [seeded, 3].min
    assert_select 'span.pagination a', { minimum: 1 }
  ensure
    Setting.per_page_options = '25,50,100'
  end
end
