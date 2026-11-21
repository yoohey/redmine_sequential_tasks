Redmine::Plugin.register :redmine_sequential_tasks do
  name 'Redmine Sequential Tasks Plugin'
  author 'yoohey'
  description 'Visualizes and manages multi-stage sequential tasks with stage timelines and progress tracking.'
  version '0.10.0'
  url 'https://github.com/yoohey/redmine_sequential_tasks'
  author_url 'https://github.com/yoohey'

  requires_redmine version_or_higher: '6.0.0'

  project_module :sequential_tasks do
    permission :view_sequential_tasks, { sequential_tasks: [:index], sequential_task_analysis: [:index], sequential_task_networks: [:show] }, public: true
    # Adjust the standard days of the stages for this project (a project manager)
    permission :manage_sequential_tasks, { sequential_task_project_steps: [:update] }, require: :member
  end

  menu :project_menu, :sequential_tasks,
       { controller: 'sequential_tasks', action: 'index' },
       caption: proc { RedmineSequentialTasks::TabLabel.text }, # an administrator may rename it
       after: :issues,
       param: :project_id

  menu :admin_menu, :sequential_task_settings,
       { controller: 'sequential_task_settings', action: 'index' },
       caption: :'sequential_tasks.menu.admin_settings',
       html: { class: 'icon icon-workflows' }

  settings default: { 'name_order' => 'redmine', 'milestone_tracker_ids' => [], 'tab_label' => '' }, partial: 'settings/sequential_tasks_settings'
end

require_relative 'lib/redmine_sequential_tasks/working_day_calculator'
require_relative 'lib/redmine_sequential_tasks/sibling_order'
require_relative 'lib/redmine_sequential_tasks/issue_tree'
require_relative 'lib/redmine_sequential_tasks/timeline_slots'
require_relative 'lib/redmine_sequential_tasks/milestones'
require_relative 'lib/redmine_sequential_tasks/band'
require_relative 'lib/redmine_sequential_tasks/screen_editing'
require_relative 'lib/redmine_sequential_tasks/stage_stats'
require_relative 'lib/redmine_sequential_tasks/stage_history'
require_relative 'lib/redmine_sequential_tasks/milestone_settings'
require_relative 'lib/redmine_sequential_tasks/tab_label'
require_relative 'lib/redmine_sequential_tasks/date_format'
require_relative 'lib/redmine_sequential_tasks/bar_style'
require_relative 'lib/redmine_sequential_tasks/network_layout'
require_relative 'lib/redmine_sequential_tasks/standard_days'
require_relative 'lib/redmine_sequential_tasks/matrix_csv'
require_relative 'lib/redmine_sequential_tasks/patches/projects_helper_patch'
require_relative 'lib/redmine_sequential_tasks/hooks'
require_relative 'lib/redmine_sequential_tasks/patches/issue_patch'

# Apply patches (init.rb is evaluated in to_prepare by Redmine::PluginLoader)
unless Issue.included_modules.include?(RedmineSequentialTasks::Patches::IssuePatch)
  Issue.include RedmineSequentialTasks::Patches::IssuePatch
end

unless ProjectsHelper.ancestors.include?(RedmineSequentialTasks::Patches::ProjectsHelperPatch)
  ProjectsHelper.prepend RedmineSequentialTasks::Patches::ProjectsHelperPatch
end
