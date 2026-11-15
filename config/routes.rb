# Routes for redmine_sequential_tasks
get 'projects/:project_id/sequential_tasks', to: 'sequential_tasks#index', as: 'project_sequential_tasks'
resources :sequential_task_settings, only: [:index, :edit, :update] do
  member { patch :enabled } # the checkbox of the list: switch a tracker on or off at once
end
put 'projects/:project_id/sequential_task_project_steps', to: 'sequential_task_project_steps#update', as: 'project_sequential_task_project_steps'
put 'issues/:issue_id/sequential_task_stages', to: 'sequential_task_stages#update', as: 'issue_sequential_task_stages'
post 'issues/:issue_id/sequential_task_branches', to: 'sequential_task_branches#create', as: 'issue_sequential_task_branches'
put 'projects/:project_id/sequential_tasks/order', to: 'sequential_task_orders#update', as: 'project_sequential_task_order'
put 'projects/:project_id/sequential_tasks/version', to: 'sequential_task_versions#update', as: 'project_sequential_task_version'
get 'projects/:project_id/sequential_tasks/network', to: 'sequential_task_networks#show', as: 'project_sequential_task_network'
get 'projects/:project_id/sequential_tasks/analysis', to: 'sequential_task_analysis#index', as: 'project_sequential_task_analysis'
