# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The export is a different rendering of the same history the search page lists
# as issues: one row per interval, with the issue's context. These tests go
# through the full stack so routing, the format extension, the export module
# and the i18n headers are all exercised together.
class StatusExportTest < Redmine::IntegrationTest
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    Role.find(1).add_permission! :search_status_history
    log_user('jsmith', 'jsmith')
    @project = Project.find(1)
    @issue = Issue.where(project_id: @project.id).visible(User.find(2)).first
  end

  # Two intervals: the creation row (no previous status) and a change into
  # status 2. The change is what the search filter matches.
  def seed(issue = @issue)
    IssueStatusHistory.create!(issue: issue, status_id: 1, user_id: 2, from: 3.days.ago)
    IssueStatusHistory.create!(issue: issue, status_id: 2, previous_status_id: 1,
                               user_id: 2, from: 2.days.ago)
  end

  def search_url(format)
    "/projects/#{@project.identifier}/issue_status_history/search.#{format}?" +
      { search: 1, status_to: 2, date_from: 10.years.ago.to_date.to_s }.to_query
  end

  test 'the search exports the matching history as CSV' do
    seed
    get search_url('csv')

    assert_response :success
    assert_match %r{text/csv}, response.content_type

    rows = CSV.parse(response.body.b)
    header = rows.first.map { |cell| cell.to_s.sub(/\A\xEF\xBB\xBF/, '') }
    assert_includes header, 'Tracker'
    assert_includes header, 'Status to'
    assert_includes header, 'Changed on'
    assert_includes header, 'Ended on'
    assert_equal 2, rows.size # header + one matching interval
    assert_equal @issue.id.to_s, rows.last.first
    assert_equal IssueStatus.find(2).name, rows.last[4]
  end

  test 'the search exports the matching history as PDF' do
    seed
    get search_url('pdf')

    assert_response :success
    assert_match %r{application/pdf}, response.content_type
    assert_match(/\A%PDF/, response.body)
  end

  test 'the export contains exactly the intervals the filters match' do
    seed
    other = Issue.where(project_id: @project.id).visible(User.find(2)).second
    # A change into a status the filter does not select must not be exported.
    IssueStatusHistory.create!(issue: other, status_id: 3, previous_status_id: 1,
                               user_id: 2, from: 2.days.ago)

    get search_url('csv')

    assert_response :success
    rows = CSV.parse(response.body.b)
    assert_equal 2, rows.size # header + one matching interval
    assert_equal @issue.id.to_s, rows.last.first
    refute_equal other.id.to_s, rows.last.first
  end

  test 'a single issue exports its full history as CSV' do
    seed
    get "/issues/#{@issue.id}/status_history.csv"

    assert_response :success
    assert_match %r{text/csv}, response.content_type
    assert_match(/Status to/, response.body)
    assert_equal 3, response.body.lines.reject(&:blank?).size # header + 2 intervals
  end

  test 'a single issue exports its full history as PDF' do
    seed
    get "/issues/#{@issue.id}/status_history.pdf"

    assert_response :success
    assert_match %r{application/pdf}, response.content_type
    assert_match(/\A%PDF/, response.body)
  end

  test 'the timeline offers the export links to a permitted user' do
    seed
    get "/issues/#{@issue.id}"

    assert_response :success
    assert_select "a[href='/issues/#{@issue.id}/status_history.csv']", 1
    assert_select "a[href='/issues/#{@issue.id}/status_history.pdf']", 1
  end

  test 'the export requires the project permission' do
    seed
    Role.find(1).remove_permission! :search_status_history

    get search_url('csv')
    assert_response :forbidden

    get "/issues/#{@issue.id}/status_history.csv"
    assert_response :forbidden
  end

  test 'an export without a search parameter returns an empty document, not an error' do
    seed
    get "/projects/#{@project.identifier}/issue_status_history/search.csv"

    assert_response :success
    assert_match %r{text/csv}, response.content_type
    # Header only: the search was never submitted.
    assert_equal 1, response.body.lines.reject(&:blank?).size
  end
end
