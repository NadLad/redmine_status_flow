# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class IssueStatusHistoryTest < ActiveSupport::TestCase
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    @issue = Issue.find(1)
    @user = User.find(2)
  end

  test 'stores the initial status without a previous status or journal' do
    history = IssueStatusHistory.create!(
      issue: @issue,
      status: @issue.status,
      user: @user,
      from: Time.zone.parse('2026-08-01 10:00')
    )

    assert_nil history.previous_status
    assert_nil history.journal
    assert_equal history.from, @issue.reload.last_status_update
  end

  test 'records a journal status change and closes the previous interval' do
    previous = IssueStatusHistory.create!(
      issue: @issue,
      status_id: 1,
      user: @user,
      from: Time.zone.parse('2026-08-01 10:00')
    )
    changed_at = Time.zone.parse('2026-08-02 11:30')
    journal = Journal.create!(journalized: @issue, user: @user, created_on: changed_at)

    JournalDetail.create!(journal: journal, property: 'attr', prop_key: 'status_id',
                          old_value: '1', value: '2')

    history = IssueStatusHistory.find_by!(journal_id: journal.id)
    assert_equal 2, history.status_id
    assert_equal 1, history.previous_status_id
    assert_equal changed_at, previous.reload.to
    assert_equal changed_at, @issue.reload.last_status_update
  end

  test 'does not create duplicate history for the same journal' do
    journal = Journal.create!(journalized: @issue, user: @user, created_on: Time.current)
    attributes = { journal: journal, property: 'attr', prop_key: 'status_id', old_value: '1', value: '2' }

    JournalDetail.create!(attributes)
    JournalDetail.create!(attributes)

    assert_equal 1, IssueStatusHistory.where(journal_id: journal.id).count
  end

  test 'search is scoped to project and date range' do
    match = IssueStatusHistory.create!(issue: @issue, status_id: 2, previous_status_id: 1,
                                       user: @user, from: Time.zone.parse('2026-08-03 12:00'))
    other_issue = Issue.where(project_id: 2).first
    IssueStatusHistory.create!(issue: other_issue, status_id: 2, previous_status_id: 1,
                               user: @user, from: match.from)

    issues = IssueStatusHistory.search_changes(Project.find(1), 2, Date.new(2026, 8, 3), 1,
                                                Date.new(2026, 8, 3), @user)

    assert_equal [@issue.id], issues.pluck(:id)
  end

  # The export serialises intervals, not the distinct issues the search page
  # lists, so it needs its own scope with the same filters and visibility.
  test 'search_intervals returns the matching intervals scoped to visible issues' do
    match = IssueStatusHistory.create!(issue: @issue, status_id: 2, previous_status_id: 1,
                                       user: @user, from: Time.zone.parse('2026-08-03 12:00'))
    other_issue = Issue.where(project_id: 2).first
    IssueStatusHistory.create!(issue: other_issue, status_id: 2, previous_status_id: 1,
                               user: @user, from: match.from)

    intervals = IssueStatusHistory.search_intervals(Project.find(1), 2, Date.new(2026, 8, 3), 1,
                                                    Date.new(2026, 8, 3), @user)

    assert_equal [match.id], intervals.map(&:id)
    assert_kind_of IssueStatusHistory, intervals.first
  end

  test 'adds the status date filter and column once' do
    query = IssueQuery.new(project: Project.find(1), user: @user)

    assert query.available_filters.key?('last_status_update')
    assert_equal 1, query.available_filters.keys.count('last_status_update')
    # The column is registered on the class (Query.add_available_column) and
    # memoized per instance, so asking twice must not duplicate it either.
    assert_equal 1, query.available_columns.count { |column| column.name == :last_status_update }
    assert_equal 1, query.available_columns.count { |column| column.name == :last_status_update }
  end
end
