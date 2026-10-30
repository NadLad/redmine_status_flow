# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The matrix is an aggregate, so an off-by-one here silently changes a report
# that looks perfectly reasonable. Counts, row shares and the heat bucket are
# pinned one by one.
class TransitionMatrixTest < ActiveSupport::TestCase
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    @project = Project.find(1)
    @user = User.find(2)
    @issues = Issue.where(project_id: @project.id).visible(@user).limit(8).to_a
    @base = Time.zone.parse('2026-08-10 09:00')
  end

  def transition(from_status:, to_status:, issue: nil)
    IssueStatusHistory.create!(issue: issue || @issues.shift, status_id: to_status,
                               previous_status_id: from_status, user_id: @user.id,
                               from: @base, to: @base + 1.day)
  end

  def report(from: Date.new(2026, 8, 1), to: Date.new(2026, 8, 31))
    RedmineStatusHistory::TransitionMatrix.report(@project, from: from, to: to, user: @user)
  end

  def status(id)
    IssueStatus.find(id)
  end

  # New -> Assigned three times, New -> Resolved once, Assigned -> Resolved twice.
  def seed_matrix
    3.times { transition(from_status: 1, to_status: 2) }
    transition(from_status: 1, to_status: 3)
    2.times { transition(from_status: 2, to_status: 3) }
  end

  test 'counts each from -> to pair' do
    seed_matrix
    matrix = report

    assert_equal 3, matrix.cell(status(1), status(2))
    assert_equal 1, matrix.cell(status(1), status(3))
    assert_equal 2, matrix.cell(status(2), status(3))
    assert_equal 0, matrix.cell(status(2), status(1))
    assert_equal 6, matrix.total
  end

  test 'aggregates rows and columns' do
    seed_matrix
    matrix = report

    assert_equal 4, matrix.row_total(status(1))
    assert_equal 2, matrix.row_total(status(2))
    assert_equal 3, matrix.column_total(status(3))
    assert_equal 0, matrix.column_total(status(1))
  end

  test 'computes the share of the row and the heat bucket' do
    seed_matrix
    matrix = report

    assert_in_delta 0.75, matrix.share(status(1), status(2)), 0.001
    assert_in_delta 0.25, matrix.share(status(1), status(3)), 0.001
    assert_in_delta 1.0, matrix.share(status(2), status(3)), 0.001

    assert_equal 4, matrix.heat(status(1), status(2))
    assert_equal 2, matrix.heat(status(1), status(3))
    assert_equal 5, matrix.heat(status(2), status(3))
    assert_equal 0, matrix.heat(status(2), status(1))
  end

  test 'ignores creation rows, other projects and intervals outside the range' do
    seed_matrix
    other_project_issue = Issue.where(project_id: 2).first

    # Creation row: no previous status, so it is an origin, not a transition.
    IssueStatusHistory.create!(issue: @issues.shift, status_id: 1, user_id: @user.id, from: @base)
    transition(from_status: 1, to_status: 2, issue: other_project_issue)
    IssueStatusHistory.create!(issue: @issues.shift, status_id: 2, previous_status_id: 1,
                               user_id: @user.id, from: @base - 90.days, to: @base - 89.days)

    matrix = report

    assert_equal 6, matrix.total
    assert_equal 3, matrix.cell(status(1), status(2))
  end

  test 'sorts the statuses by name, not by id' do
    seed_matrix

    names = report.statuses.map(&:name)

    assert_equal names.sort_by(&:downcase), names
  end

  test 'reports empty when no transition started in the range' do
    seed_matrix

    matrix = report(from: Date.new(2020, 1, 1), to: Date.new(2020, 1, 31))

    assert_predicate matrix, :empty?
    assert_empty matrix.statuses
    assert_equal 0, matrix.total
  end
end
