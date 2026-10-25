require 'redmine'

plugin_lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(plugin_lib) unless $LOAD_PATH.include?(plugin_lib)

require 'redmine_status_history/patches/issue_patch'
require 'redmine_status_history/patches/issue_query_patch'
require 'redmine_status_history/patches/journal_detail_patch'

unless Issue.include?(RedmineStatusHistory::Patches::IssuePatch)
  Issue.include(RedmineStatusHistory::Patches::IssuePatch)
end
unless IssueQuery.include?(RedmineStatusHistory::Patches::IssueQueryPatch)
  IssueQuery.include?(RedmineStatusHistory::Patches::IssueQueryPatch)
end
unless JournalDetail.include?(RedmineStatusHistory::Patches::JournalDetailPatch)
  JournalDetail.include?(RedmineStatusHistory::Patches::JournalDetailPatch)
end

require 'redmine_status_history/hooks/view_issues_index_bottom'

Redmine::Plugin.register :redmine_status_flow do
  name 'Redmine Status Flow'
  author 'Nader Lad (fork of Redmine Services)'
  description 'Status timeline, duration metrics and native status filters for issues'
  version '3.0.0'
  url 'https://github.com/NadLad/redmine_status_flow'
  author_url 'https://github.com/NadLad'
  # requires_redmine accepts a Range, which gives the fork a real upper bound:
  # Redmine above 7.0 is refused at boot instead of loading unverified code.
  requires_redmine version: '5.0'..'7.0'

  project_module :issue_tracking do
    permission :search_status_history,
               { status_histories: %i[search show_history] },
               require: :member
  end
end
