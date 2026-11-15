# frozen_string_literal: true

module RedmineSequentialTasks
  # For the controllers that change issues from the project screen (reorder, move to another version): the project
  # is found by its identifier, the screen's module must be on, and the user must be allowed to edit issues.
  module ScreenEditing
    def self.included(base)
      base.before_action :find_project_by_project_id
      base.before_action :authorize_screen_editing
    end

    private

    def authorize_screen_editing
      return render_404 unless @project.module_enabled?(:sequential_tasks)

      deny_access unless User.current.allowed_to?(:edit_issues, @project)
    end
  end
end
