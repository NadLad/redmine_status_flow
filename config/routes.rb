Rails.application.routes.draw do
  match 'projects/:project_id/issue_status_history/search',
        to: 'status_histories#search', via: %i[get post], as: 'search_status_history'

  # Per-issue export, linked from the inline timeline. The format extension
  # (.csv/.pdf) selects the renderer.
  match 'issues/:issue_id/status_history',
        to: 'status_histories#issue_export', via: :get, as: 'status_history_export'
end
