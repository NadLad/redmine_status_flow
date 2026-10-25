module RedmineStatusHistory
  module Hooks
    # Renders the issue's status timeline inline, at the bottom of the
    # attributes block of the issue show page.
    #
    # The upstream plugin rendered it through a remote link + showModal() +
    # a .js.erb template. That path is gone: `view_issues_show_details_bottom`
    # exists in every supported version (5.0 through 7.0, verified in each
    # stable branch), so there is no version left that would need the modal
    # fallback.
    class ViewIssuesShowDetailsBottom < Redmine::Hook::ViewListener
      render_on :view_issues_show_details_bottom, partial: 'hooks/issue_status_flow_timeline'
    end
  end
end
