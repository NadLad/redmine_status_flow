module RedmineStatusHistory
  module Hooks
    # Redmine does not auto-include a plugin's stylesheets, and a plugin's
    # assets/ directory is served under assets/<plugin_id>/ (see the
    # redmine_extension_paths registration in config/initializers/30-redmine.rb).
    # The timeline is plain markup, so this one link is the plugin's whole
    # front-end footprint: no JavaScript is shipped.
    class ViewLayoutsBaseHtmlHead < Redmine::Hook::ViewListener
      render_on :view_layouts_base_html_head, partial: 'hooks/status_flow_stylesheet'
    end
  end
end
