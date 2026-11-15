# frozen_string_literal: true

module RedmineSequentialTasks
  module Patches
    # A tab "Sequential tasks" in the settings of a project, for those who may adjust the standard days
    module ProjectsHelperPatch
      def project_settings_tabs
        tabs = super
        if @project&.module_enabled?(:sequential_tasks) && User.current.allowed_to?(:manage_sequential_tasks, @project)
          tabs << { name: 'sequential_tasks', action: :manage_sequential_tasks,
                    partial: 'sequential_task_project_steps/tab', label: :'sequential_tasks.project_settings.tab' }
        end
        tabs
      end
    end
  end
end
