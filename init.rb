require 'redmine'

plugin_lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(plugin_lib) unless $LOAD_PATH.include?(plugin_lib)

require 'redmine_status_history/patches/issue_patch'
require 'redmine_status_history/patches/issue_query_patch'
require 'redmine_status_history/patches/journal_detail_patch'
require 'redmine_status_history/export'
require 'redmine_status_history/metrics'
require 'redmine_status_history/aging'
require 'redmine_status_history/transition_matrix'

# Each patch module exposes InstanceMethods, and its `included` hook puts that
# module in the class ancestors (included for Issue/JournalDetail, prepended for
# IssueQuery). Checking the hook target rather than the wrapper is what makes
# this idempotent: including the wrapper twice would re-register the callbacks.
{
  Issue => RedmineStatusHistory::Patches::IssuePatch,
  IssueQuery => RedmineStatusHistory::Patches::IssueQueryPatch,
  JournalDetail => RedmineStatusHistory::Patches::JournalDetailPatch
}.each do |target, patch|
  target.include(patch) unless target.ancestors.include?(patch.const_get(:InstanceMethods))
end

# Columns are registered on the class, not on an instance: IssueQuery#available_columns
# memoizes a dup of the class array, so mutating an instance's array only lasted
# for that one query. class_attribute shares the array with Query, hence the dup
# before appending -- otherwise the column would leak into every query class.
unless IssueQuery.available_columns.any? { |column| column.name == :last_status_update }
  IssueQuery.available_columns = IssueQuery.available_columns.dup
  IssueQuery.add_available_column(
    QueryColumn.new(:last_status_update,
                    sortable: "#{Issue.table_name}.last_status_update",
                    caption: :field_last_status_update)
  )
end

require 'redmine_status_history/hooks/view_issues_index_bottom'
require 'redmine_status_history/hooks/view_issues_show_details_bottom'
require 'redmine_status_history/hooks/view_layouts_base_html_head'

Redmine::Plugin.register :redmine_status_flow do
  name 'Redmine Status Flow'
  author 'Nader Lad (fork of Redmine Services)'
  description 'Status timeline, duration metrics and native status filters for issues'
  version '3.1.0'
  url 'https://github.com/NadLad/redmine_status_flow'
  author_url 'https://github.com/NadLad'
  # requires_redmine accepts a Range, which gives the fork a real upper bound:
  # Redmine above 7.0 is refused at boot instead of loading unverified code.
  requires_redmine version: '5.0'..'7.0'

  # Aging thresholds. Statuses are matched by name, not id: ids are
  # per-installation, names are what the administrator sees in this form.
  # A status without its own line uses aging_default_days.
  settings default: {
    'aging_default_days' => '7',
    'aging_thresholds' => ''
  }

  project_module :issue_tracking do
    permission :search_status_history,
               { status_histories: %i[search issue_export metrics aging transitions] },
               require: :member
  end
end
