class SequentialTaskSettingsController < ApplicationController
  layout 'admin'
  before_action :require_admin

  def index
    @trackers = Tracker.sorted
    @settings = SequentialTaskSetting.includes(steps: :status).index_by(&:tracker_id)
  end

  def edit
    @tracker = Tracker.find(params[:id])
    @setting = SequentialTaskSetting.find_or_initialize_by(tracker_id: @tracker.id)
    load_screen_data
    @bar_style = @setting.bar_style
  end

  # Switches a tracker on or off from the list. A tracker with no stages cannot be switched on (nothing to lay out).
  def enabled
    tracker = Tracker.find(params[:id])
    setting = SequentialTaskSetting.find_or_initialize_by(tracker_id: tracker.id)
    on = params[:enabled] == '1'
    if on && setting.steps.none?
      flash[:error] = l('sequential_tasks.settings.cannot_enable_without_stages')
    else
      setting.update!(enabled: on)
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to sequential_task_settings_path
  end

  def update
    @tracker = Tracker.find(params[:id])
    @setting = SequentialTaskSetting.find_or_initialize_by(tracker_id: @tracker.id)

    @setting.enabled = params[:enabled] == '1'
    @setting.bar_style = RedmineSequentialTasks::BarStyle.normalize(params[:bar_style]) # of this tracker
    rows = submitted_steps
    switched_off = @setting.enabled? && rows.empty? # a tracker with no stage cannot be on (nothing to lay out)
    @setting.enabled = false if switched_off

    ActiveRecord::Base.transaction do
      @setting.save!

      # Delete existing steps and recreate them from the submitted order
      @setting.steps.destroy_all
      rows.each_with_index do |row, index|
        @setting.steps.create!(row.merge(position: index + 1))
      end
    end

    flash[:notice] = l(:notice_successful_update)
    flash[:warning] = l('sequential_tasks.settings.switched_off_without_stages') if switched_off
    redirect_to sequential_task_settings_path
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.message
    load_screen_data # what is stored (the failed save was rolled back)
    @bar_style = @setting.bar_style
    render :edit
  end

  private

  # The submitted stages as attribute hashes, in the order of the form. Rows without a known status are dropped; the
  # days are kept within 1..365 (the first stage: 0..365) and a color that is not #rrggbb falls back to the default.
  def submitted_steps
    return [] unless params[:steps].is_a?(Array)

    known = IssueStatus.where(id: params[:steps].filter_map { |sp| sp[:status_id] if sp.respond_to?(:key?) }).pluck(:id)
    first = true
    params[:steps].filter_map do |step_params|
      next unless step_params.respond_to?(:key?) && known.include?(step_params[:status_id].to_i)

      color = step_params[:color].to_s
      lowest = first ? 0 : 1 # only the first stage may be zero days: a wait for somebody to pick the issue up
      first = false
      { status_id: step_params[:status_id].to_i,
        default_duration_days: step_params[:default_duration_days].to_i.clamp(lowest, 365),
        color: color.match?(SequentialTaskStep::COLOR_FORMAT) ? color : SequentialTaskStep::DEFAULT_COLOR }
    end
  end

  # The rows of the edit screen: the statuses the tracker's workflow uses, plus any status a stage already has
  # (kept visible so it can be seen and removed). The stages come first in their stored order, then the other
  # statuses in the order of the Redmine statuses. The order of the rows is the order of the stages (it is dragged).
  def load_screen_data
    @steps_by_status = @setting.steps.reload.index_by(&:status_id)
    @workflow_status_ids = @tracker.issue_statuses.map(&:id)
    sorted = IssueStatus.sorted.to_a
    staged = @setting.steps.sort_by(&:position).filter_map { |step| sorted.find { |st| st.id == step.status_id } }
    others = sorted.select { |st| @workflow_status_ids.include?(st.id) && !@steps_by_status.key?(st.id) }
    @statuses = staged + others
  end
end
