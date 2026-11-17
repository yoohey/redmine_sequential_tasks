# frozen_string_literal: true

class SequentialTaskStagesController < ApplicationController
  before_action :find_issue
  before_action :authorize_edit_issue

  def update
    stages = @issue.issue_stages.order(:position).to_a
    if stages.empty?
      flash[:error] = l('sequential_tasks.flash.no_stages')
      finish
      return
    end

    # Completed stages stay as they are; only the current stage and the later ones are rescheduled
    summary = RedmineSequentialTasks::ProgressSummary.new(@issue, stages, User.current.today)
    rescheduler = RedmineSequentialTasks::StageRescheduler.new(stages, @issue.closed? ? nil : summary.current_stage)
    # The due date follows the last stage; when the workflow makes it read-only, nothing is changed
    unless @issue.safe_attribute?('due_date', User.current)
      flash[:error] = l('sequential_tasks.flash.due_not_changeable')
      finish
      return
    end

    unless rescheduler.adjustable_any?
      flash[:error] = l('sequential_tasks.flash.nothing_adjustable')
      finish
      return
    end

    # no working day within about half a year: the plan cannot be built
    unless RedmineSequentialTasks::WorkingDayCalculator.schedulable?(summary.current_stage&.planned_start_date || User.current.today)
      flash[:error] = l('sequential_tasks.flash.no_working_day')
      finish
      return
    end

    durations = {}
    all_days = {} # stage id => count the non-working days too; only for the stages that are sent
    stage_params = params[:stages]
    stage_params = {} unless stage_params.is_a?(ActionController::Parameters) # e.g. stages=abc: nothing sent
    stage_params.each_pair do |stage_id, sp|
      next unless sp.is_a?(ActionController::Parameters)

      durations[stage_id.to_i] = sp[:duration_days] if sp.key?(:duration_days)
      all_days[stage_id.to_i] = (sp[:count_non_working].to_s == '1') if sp.key?(:count_non_working)
    end

    # A new start date, only while no stage has finished; nil when it is not changed
    new_start = requested_start_date(stages, rescheduler)
    if new_start == :out_of_range
      flash[:error] = l('sequential_tasks.flash.date_out_of_range', years: RedmineSequentialTasks::WorkingDayCalculator::DATE_RANGE_YEARS)
      finish
      return
    end
    if new_start == :refused
      flash[:error] = l('sequential_tasks.flash.start_not_changeable')
      finish
      return
    end

    # "fixed_due": keep the due date where it is, shrinking or growing the other stages instead of it.
    # Anything else (the default): push the rest, moving the due date along (the original behaviour).
    fixed_due = params[:mode] == 'fixed_due'

    changes_notes = []
    old_due_date = @issue.due_date
    old_start_date = @issue.start_date

    # The days of each stage as they were, before a switch of the counting changes what its dates mean
    old_durations = stages.to_h { |s| [s.id, rescheduler.current_duration(s)] }
    count_notes = []
    stages.each do |stage|
      next unless all_days.key?(stage.id) && rescheduler.adjustable?(stage) && stage.all_days? != all_days[stage.id]

      stage.count_non_working = all_days[stage.id]
      count_notes << l('sequential_tasks.journal.count_line',
                       stage: stage.status&.name || l('sequential_tasks.journal.stage_fallback', position: stage.position),
                       value: l(all_days[stage.id] ? 'sequential_tasks.journal.count_all' : 'sequential_tasks.journal.count_working'))
    end

    ActiveRecord::Base.transaction do
      schedules =
        if fixed_due
          # The due date (the end of the last stage) stays; a moved start or a stage that counts every day changes the
          # room before it, and the slack takes that up
          rescheduler.call_fixed(durations, start_date: new_start)
        else
          rescheduler.call(durations, new_start)
        end
      schedules.each do |schedule|
        stage = schedule.stage
        old_start = stage.planned_start_date
        old_end = stage.planned_end_date
        old_duration = old_durations[stage.id]

        # Check if duration or dates changed
        if old_duration != schedule.duration || old_start != schedule.start_date || old_end != schedule.end_date
          status_name = stage.status&.name || l('sequential_tasks.journal.stage_fallback', position: stage.position)
          changes_notes << l('sequential_tasks.journal.stage_line',
                             stage: status_name,
                             from_days: old_duration || '?',
                             from_range: date_range(old_start, old_end),
                             to_days: schedule.duration,
                             to_range: date_range(schedule.start_date, schedule.end_date))
        end

        stage.update!(
          planned_start_date: schedule.start_date,
          planned_end_date: schedule.end_date
        )
      end

      changes_notes.concat(count_notes)
      if new_start
        changes_notes.unshift(l('sequential_tasks.journal.start_line',
                                from: old_start_date ? RedmineSequentialTasks::DateFormat.full(old_start_date) : l('sequential_tasks.journal.unset'),
                                to: RedmineSequentialTasks::DateFormat.full(new_start)))
        # Saving it also runs IssuePatch#plan_sequential_date_changes, which plans the stages again from
        # this date with the durations just stored: the same dates
        @issue.safe_attributes = { 'start_date' => new_start.to_s } # for User.current
        # The 0-day wait is a point at the start; it is never in the schedules (not adjustable)
        stages.select(&:zero_day).each { |s| s.update!(planned_start_date: new_start, planned_end_date: new_start) }
      end

      new_due_date = stages.last.planned_end_date
      if old_due_date != new_due_date
        changes_notes << l('sequential_tasks.journal.due_line',
                           from: old_due_date ? RedmineSequentialTasks::DateFormat.full(old_due_date) : l('sequential_tasks.journal.unset'),
                           to: RedmineSequentialTasks::DateFormat.full(new_due_date))
        # through safe_attributes: the workflow may make the due date read-only
        @issue.safe_attributes = { 'due_date' => new_due_date.to_s } # for User.current
      end

      # Add journal note if changes occurred
      if changes_notes.any?
        notes = l('sequential_tasks.journal.title') + "\n" + changes_notes.join("\n")
        @issue.init_journal(User.current, notes)
        @issue.save!
        flash[:notice] = l('sequential_tasks.flash.schedule_updated')
      else
        flash[:notice] = l('sequential_tasks.flash.no_changes')
      end
    end

    finish
  rescue RedmineSequentialTasks::StageRescheduler::CannotFit
    flash[:error] = l('sequential_tasks.flash.cannot_fit_due_date')
    finish
  rescue RedmineSequentialTasks::WorkingDayCalculator::NoWorkingDay
    flash[:error] = l('sequential_tasks.flash.no_working_day')
    finish
  rescue ActiveRecord::StaleObjectError
    flash[:error] = l(:notice_issue_update_conflict) # somebody else saved the issue meanwhile
    finish
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e # NotSaved: refused in a callback
    # Only validation errors are shown to the user; other exceptions go to Redmine's error page and log
    flash[:error] = l('sequential_tasks.flash.update_failed', errors: e.record.errors.full_messages.join(', '))
    finish
  end

  private

  # Back to the issue page; from the project timeline's adjust mode (a fetch) a JSON answer instead, with the
  # message that would have been flashed
  def finish
    if request.xhr?
      error = flash[:error]
      notice = flash[:notice]
      flash.discard
      render json: { ok: error.blank?, error: error, notice: notice }
    else
      redirect_to issue_path(@issue)
    end
  end

  # The start date sent from the adjustment screen: nil when absent, unchanged or unreadable,
  # :refused when it would change but may not (a stage has finished, or the workflow forbids it), else the date
  # moved to a working day.
  def requested_start_date(stages, rescheduler)
    raw = params[:start_date].presence
    return nil unless raw

    date = Date.iso8601(raw.to_s) rescue nil # rubocop:disable Style/RescueModifier
    return nil unless date
    return :out_of_range unless RedmineSequentialTasks::WorkingDayCalculator.date_in_range?(date)

    date = RedmineSequentialTasks::WorkingDayCalculator.next_working_day(date)
    current = stages.first.planned_start_date
    return nil if date == current

    return :refused unless rescheduler.start_changeable? && @issue.safe_attribute?('start_date', User.current)

    date
  end

  # "11/04〜11/05" (ja) / "11/04 - 11/05" (en)
  def date_range(from_date, to_date)
    l('sequential_tasks.table.range', from: RedmineSequentialTasks::DateFormat.short(from_date), to: RedmineSequentialTasks::DateFormat.short(to_date))
  end

  def find_issue
    @issue = Issue.visible.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_edit_issue
    deny_access unless User.current.allowed_to?(:edit_issues, @project) && @project.module_enabled?(:sequential_tasks)
  end
end
