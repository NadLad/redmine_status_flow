Rails.application.routes.draw do
  match 'projects/:project_id/issue_status_history/search',
        to: 'status_histories#search', via: %i[get post], as: 'search_status_history'

  # Duration metrics for the project. A separate page from the search: the
  # search answers "which issues changed", this answers "where did the time go".
  match 'projects/:project_id/issue_status_history/metrics',
        to: 'status_histories#metrics', via: :get, as: 'status_history_metrics'

  # Issues that have been in their current status too long, against the
  # per-status thresholds from the plugin settings.
  match 'projects/:project_id/issue_status_history/aging',
        to: 'status_histories#aging', via: :get, as: 'status_history_aging'

  # from -> to transition counts for the period, as a server-rendered matrix.
  match 'projects/:project_id/issue_status_history/transitions',
        to: 'status_histories#transitions', via: :get, as: 'status_history_transitions'

  # Per-issue export, linked from the inline timeline. The format extension
  # (.csv/.pdf) selects the renderer.
  match 'issues/:issue_id/status_history',
        to: 'status_histories#issue_export', via: :get, as: 'status_history_export'
end
