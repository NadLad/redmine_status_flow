# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# The report aggregates durations that no longer belong to a single interval,
# so every number here is checked against an exact expected value. A mean that
# silently includes another project's intervals, or a p90 that interpolates
# when it claims nearest rank, is the kind of error a human cannot spot by
# reading the table.
class MetricsTest < ActiveSupport::TestCase
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    @project = Project.find(1)
    @user = User.find(2)
    @issue = Issue.where(project_id: @project.id).visible(@user).first
    @base = Time.zone.parse('2026-08-01 09:00')
  end

  def interval(status_id:, days:, issue: @issue, from: @base)
    IssueStatusHistory.create!(issue: issue, status_id: status_id, user_id: @user.id,
                               from: from, to: from + days.days)
  end

  def report(from: Date.new(2026, 8, 1), to: Date.new(2026, 8, 31), now: @base + 30.days)
    RedmineStatusHistory::Metrics.report(@project, from: from, to: to, user: @user, now: now)
  end

  def row_for(status_id, **options)
    report(**options).find { |row| row.status_label == IssueStatus.find(status_id).name }
  end

  test 'computes count, total, mean, median, p90 and max per status' do
    [1, 2, 3, 4].each { |days| interval(status_id: 1, days: days) }

    row = row_for(1)

    assert_equal 4, row.count
    assert_equal 10 * 86_400, row.total
    assert_in_delta 2.5 * 86_400, row.mean, 0.001
    assert_in_delta 2.5 * 86_400, row.median, 0.001
    assert_equal 4 * 86_400, row.p90
    assert_equal 4 * 86_400, row.max
  end

  # nearest rank: ceil(0.9 * 10) = 9, so the ninth smallest value, not a value
  # interpolated between the ninth and the tenth.
  test 'p90 uses the nearest-rank definition' do
    (1..10).each { |days| interval(status_id: 2, days: days) }

    assert_equal 9 * 86_400, row_for(2).p90
  end

  test 'measures a running interval up to now' do
    IssueStatusHistory.create!(issue: @issue, status_id: 3, user_id: @user.id, from: @base)

    row = row_for(3, now: @base + 3.days + 6.hours)

    assert_equal 1, row.count
    assert_equal 3 * 86_400 + 6 * 3_600, row.max
  end

  test 'ignores intervals from another project and outside the range' do
    other_issue = Issue.where(project_id: 2).first
    interval(status_id: 1, days: 1)
    interval(status_id: 1, days: 1, issue: other_issue)
    interval(status_id: 1, days: 1, from: @base - 60.days)

    assert_equal 1, row_for(1).count
  end

  test 'orders the slowest status first' do
    interval(status_id: 1, days: 1)
    interval(status_id: 2, days: 5)

    assert_equal [IssueStatus.find(2).name, IssueStatus.find(1).name], report.map(&:status_label)
  end

  test 'returns no row for a range without intervals' do
    interval(status_id: 1, days: 1)

    assert_empty report(from: Date.new(2020, 1, 1), to: Date.new(2020, 1, 31))
  end

  # duration_label delegates here now; the refactor must not change a single
  # rendered string.
  test 'formats a raw duration the way an interval label did' do
    I18n.with_locale(:en) do
      assert_equal '< 1min', IssueStatusHistory.format_duration(10)
      assert_equal '2min', IssueStatusHistory.format_duration(120)
      assert_equal '1h 2min', IssueStatusHistory.format_duration(3_720)
      assert_equal '1d 1h', IssueStatusHistory.format_duration(90_000)
    end
  end
end
