# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Thresholds are configuration: they are parsed from a free-text setting, keyed
# by status name, and every status without a line must fall back to the
# default. A parser that silently swallows a typo turns an SLA into decoration.
class AgingTest < ActiveSupport::TestCase
  fixtures :all

  setup do
    IssueStatusHistory.delete_all
    @project = Project.find(1)
    @user = User.find(2)
    @issues = Issue.where(project_id: @project.id).visible(@user).limit(5).to_a
    @now = Time.zone.parse('2026-08-20 12:00')
    Setting.plugin_redmine_status_flow = {}
  end

  def open_interval(status_id:, days_ago:, issue: nil)
    IssueStatusHistory.create!(issue: issue || @issues.shift, status_id: status_id,
                               user_id: @user.id, from: @now - days_ago.days, to: nil)
  end

  def entry_for(issue)
    RedmineStatusHistory::Aging.report(@project, user: @user, now: @now)
                               .find { |entry| entry.issue == issue }
  end

  # Redmine renders the plugin settings form from these defaults: a missing
  # key means no field, and no field means the threshold cannot be configured
  # at all -- which no request-level test would ever catch.
  test 'registers both threshold settings with defaults' do
    defaults = Redmine::Plugin.find(:redmine_status_flow).settings[:default]

    assert_equal '7', defaults['aging_default_days']
    assert_equal '', defaults['aging_thresholds']
  end

  test 'falls back to seven days when no default is stored' do
    assert_equal 7, RedmineStatusHistory::Aging.default_days
  end

  test 'reads the default and the per-status thresholds, ignoring junk lines' do
    Setting.plugin_redmine_status_flow = {
      'aging_default_days' => '3',
      'aging_thresholds' => "New: 10\nAssigned = 2\n\nnot a line\nResolved: zero\n"
    }

    assert_equal 3, RedmineStatusHistory::Aging.default_days
    assert_equal({ 'new' => 10, 'assigned' => 2 }, RedmineStatusHistory::Aging.thresholds)
  end

  test 'flags an issue at or past its threshold and computes full days' do
    Setting.plugin_redmine_status_flow = { 'aging_default_days' => '7', 'aging_thresholds' => 'Assigned: 2' }

    over_default_issue = @issues.first
    fresh_issue = @issues.second
    over_own_threshold_issue = @issues.third
    open_interval(status_id: 1, days_ago: 10, issue: over_default_issue)   # New, default 7
    open_interval(status_id: 1, days_ago: 3, issue: fresh_issue)           # New, default 7
    open_interval(status_id: 2, days_ago: 5, issue: over_own_threshold_issue) # Assigned, own 2

    over_default = entry_for(over_default_issue)
    assert_equal 10, over_default.days
    assert_equal 7, over_default.threshold
    assert_predicate over_default, :over?

    fresh = entry_for(fresh_issue)
    assert_equal 3, fresh.days
    refute_predicate fresh, :over?

    own = entry_for(over_own_threshold_issue)
    assert_equal 2, own.threshold
    assert_predicate own, :over?
  end

  test 'measures only complete days, so 6 days 23 hours is still 6' do
    Setting.plugin_redmine_status_flow = { 'aging_default_days' => '7', 'aging_thresholds' => '' }
    issue = @issues.first
    IssueStatusHistory.create!(issue: issue, status_id: 1, user_id: @user.id,
                               from: @now - 6.days - 23.hours, to: nil)

    assert_equal 6, entry_for(issue).days
    refute_predicate entry_for(issue), :over?
  end

  test 'ignores closed intervals, closed statuses and other projects' do
    Setting.plugin_redmine_status_flow = { 'aging_default_days' => '1', 'aging_thresholds' => '' }
    closed_issue = @issues.first
    closed_status_issue = @issues.second
    other_project_issue = Issue.where(project_id: 2).first

    IssueStatusHistory.create!(issue: closed_issue, status_id: 1, user_id: @user.id,
                               from: @now - 30.days, to: @now - 20.days)
    open_interval(status_id: 5, days_ago: 30, issue: closed_status_issue) # Closed status
    open_interval(status_id: 1, days_ago: 30, issue: other_project_issue)

    entries = RedmineStatusHistory::Aging.report(@project, user: @user, now: @now)

    assert_empty entries
  end
end
