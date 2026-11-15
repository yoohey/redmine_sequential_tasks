# frozen_string_literal: true

# The standard days of the stages that a project sets for itself, from the settings of the project
class SequentialTaskProjectStepsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  # params[:days] is { tracker_id => { status_id => days } }. An empty value, or the tracker's own value, means no
  # override. Trackers and statuses that are not in the tracker settings are ignored.
  def update
    settings = SequentialTaskSetting.where(tracker_id: @project.tracker_ids, enabled: true).includes(:steps).index_by(&:tracker_id)
    submitted = params[:days].respond_to?(:to_unsafe_h) ? params[:days].to_unsafe_h : {}

    SequentialTaskProjectStep.transaction do
      settings.each do |tracker_id, setting|
        per_status = submitted[tracker_id.to_s]
        next unless per_status.is_a?(Hash)

        setting.steps.each do |step|
          write(tracker_id, step, per_status[step.status_id.to_s])
        end
      end
    end

    flash[:notice] = l(:notice_successful_update)
    redirect_to settings_project_path(@project, tab: 'sequential_tasks')
  end

  private

  def write(tracker_id, step, value)
    row = SequentialTaskProjectStep.find_or_initialize_by(project_id: @project.id, tracker_id: tracker_id, status_id: step.status_id)
    first = step.position == step.sequential_task_setting.steps.minimum(:position) # only the first stage may be zero days
    days = value.to_s.strip.empty? ? nil : value.to_i.clamp(first ? 0 : 1, 365)
    if days.nil? || days == step.default_duration_days
      row.destroy if row.persisted?
    else
      row.update!(default_duration_days: days)
    end
  end
end
