# frozen_string_literal: true

# moves an issue to another version (or takes the version off) when it is dropped on
# another group of the timeline. A change of the issue like any other: it is in the history, the workflow's rules for
# the field apply, and a version that cannot be assigned is refused with the reason.
class SequentialTaskVersionsController < ApplicationController
  include RedmineSequentialTasks::ScreenEditing

  def update
    issue = @project.issues.visible.find_by(id: params[:issue_id])
    return render_404 unless issue

    version = nil
    if params[:version_id].present?
      version = @project.shared_versions.find_by(id: params[:version_id])
      return render(plain: l('sequential_tasks.flash.version_unknown'), status: :unprocessable_entity) unless version
    end
    return head(:no_content) if issue.fixed_version_id == version&.id

    issue.init_journal(User.current)
    issue.safe_attributes = { 'fixed_version_id' => version&.id.to_s } # for User.current
    # The workflow may make the field read-only: the attribute is then silently ignored
    unless issue.fixed_version_id == version&.id
      return render(plain: l('sequential_tasks.flash.version_not_changeable'), status: :unprocessable_entity)
    end

    if issue.save
      head :no_content
    else
      render plain: issue.errors.full_messages.join(', '), status: :unprocessable_entity
    end
  end
end
