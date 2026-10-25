Rails.application.routes.draw do
  match 'projects/:project_id/issue_status_history/search',
        to: 'status_histories#search', via: %i[get post], as: 'search_status_history'
end
