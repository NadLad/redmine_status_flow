module RedmineStatusHistory
  module Hooks
    # Redmine does not auto-include a plugin's stylesheets, so this hook adds
    # the one <link> the plugin needs. The URL differs between Redmine 5.x and
    # 6.0+ (mirrored assets vs asset pipeline), and the version check lives in
    # the partial where the reasoning is written down.
    #
    # The timeline is plain markup: the plugin ships no JavaScript.
    class ViewLayoutsBaseHtmlHead < Redmine::Hook::ViewListener
      render_on :view_layouts_base_html_head, partial: 'hooks/status_flow_stylesheet'
    end
  end
end
