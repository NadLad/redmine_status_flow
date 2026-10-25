# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The filters are SQL, so these tests run them against real rows instead of
# asserting on the generated string: a clause that reads correctly but returns
# the wrong issues is the failure mode that matters.
class IssueQueryStatusFlowTest < ActiveSupport::TestCase
  fixtures :all

  FILTERS = %w[
    status_changed_to status_changed_from status_changed_between
    time_in_current_status reopen_count
  ].freeze

  setup do
    IssueStatusHistory.delete_all
    User.current = User.find(1)
    @project = Project.find(1)
    @changed = Issue.find(2)
    @untouched = Issue.find(3)
  end

  # A Query without a name is invalid, and Query#statement drops every filter
  # when the query is invalid -- silently returning all issues.
  def query_with(field, operator, values)
    query = IssueQuery.new(name: 'status flow test', project: @project)
    query.add_filter(field, operator, values)
    query.issues.to_a.map(&:id)
  end

  def interval(issue, status_id, from:, to: nil, previous_status_id: nil, journal_id: nil)
    IssueStatusHistory.create!(
      issue_id: issue.id, status_id: status_id, previous_status_id: previous_status_id,
      journal_id: journal_id, from: from, to: to, user_id: issue.author_id
    )
  end

  def journal_for(issue)
    Journal.create!(journalized: issue, user_id: issue.author_id, notes: 'status change',
                    created_on: Time.current)
  end

  test 'registers all five filters on an issue query' do
    available = IssueQuery.new(project: @project).available_filters

    FILTERS.each { |field| assert available.key?(field), "#{field} is not registered" }
  end

  test 'the filter labels are translated, not raw field names' do
    filter = IssueQuery.new(project: @project).available_filters['status_changed_to']

    assert_equal 'Status changed to', filter[:name]
  end

  test 'status_changed_to only matches a real change, not the initial interval' do
    journal = journal_for(@changed)
    interval(@changed, 1, from: 10.days.ago, to: 9.days.ago)
    interval(@changed, 2, from: 9.days.ago, previous_status_id: 1, journal_id: journal.id)
    interval(@untouched, 2, from: 10.days.ago)

    assert_equal [@changed.id], query_with('status_changed_to', '=', ['2'])
    assert_includes query_with('status_changed_to', '!', ['2']), @untouched.id
    refute_includes query_with('status_changed_to', '!', ['2']), @changed.id
  end

  test 'status_changed_from matches on the previous status' do
    journal = journal_for(@changed)
    interval(@changed, 3, from: 9.days.ago, previous_status_id: 2, journal_id: journal.id)

    assert_equal [@changed.id], query_with('status_changed_from', '=', ['2'])
    assert_empty query_with('status_changed_from', '=', ['5'])
  end

  test 'status_changed_between matches the day of the change' do
    journal = journal_for(@changed)
    interval(@changed, 2, from: 3.days.ago, previous_status_id: 1, journal_id: journal.id)
    day = 3.days.ago.to_date

    assert_equal [@changed.id], query_with('status_changed_between', '=', [day.to_s])
    assert_empty query_with('status_changed_between', '=', [(day - 5).to_s])
  end

  test 'time_in_current_status reads the age of the open interval' do
    interval(@changed, 1, from: 10.days.ago, to: 6.days.ago)
    interval(@changed, 2, from: 6.days.ago)
    interval(@untouched, 1, from: 1.day.ago)

    assert_includes query_with('time_in_current_status', '>=', ['5']), @changed.id
    refute_includes query_with('time_in_current_status', '>=', ['5']), @untouched.id
    assert_includes query_with('time_in_current_status', '<=', ['2']), @untouched.id
    refute_includes query_with('time_in_current_status', '<=', ['2']), @changed.id
    assert_equal [@changed.id], query_with('time_in_current_status', '=', ['6'])
  end

  test 'reopen_count counts closed-to-open transitions' do
    closed_id = IssueStatus.where(is_closed: true).first.id
    journal = journal_for(@changed)
    interval(@changed, closed_id, from: 8.days.ago, previous_status_id: 1)
    interval(@changed, 1, from: 7.days.ago, previous_status_id: closed_id, journal_id: journal.id)
    interval(@untouched, 1, from: 8.days.ago)

    reopened = query_with('reopen_count', '>=', ['1'])

    assert_includes reopened, @changed.id
    refute_includes reopened, @untouched.id
    assert_includes query_with('reopen_count', '=', ['0']), @untouched.id
  end

  test 'the last_status_update column is registered once, at class level' do
    names = IssueQuery.available_columns.map(&:name)

    assert_equal 1, names.count(:last_status_update)
    # The column must not leak into other query classes through the shared
    # class_attribute array.
    refute_includes Query.available_columns.map(&:name), :last_status_update
  end
end
