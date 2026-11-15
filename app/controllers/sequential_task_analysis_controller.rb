# frozen_string_literal: true

# The analysis screen: how long issues stay in each stage, per tracker.
class SequentialTaskAnalysisController < ApplicationController
  PERIODS = [30, 90, 365].freeze # "the last N days"; no period means all of the history

  helper :sequential_tasks # the toolbar controls and the view switch
  menu_item :sequential_tasks # the project menu keeps "Sequential Tasks" selected on this screen

  before_action :find_project_by_project_id
  before_action :authorize

  def index
    @tracker_filter = params[:tracker_id].presence&.to_i
    @days = PERIODS.include?(params[:days].to_i) ? params[:days].to_i : nil

    settings = SequentialTaskSetting.where(tracker_id: @project.tracker_ids, enabled: true).includes(steps: :status).to_a
    @enabled_trackers = Tracker.where(id: settings.map(&:tracker_id)).order(:position).to_a
    rows = RedmineSequentialTasks::StageHistory.new(@project).rows(days: @days)

    shown = @tracker_filter ? @enabled_trackers.select { |t| t.id == @tracker_filter } : @enabled_trackers
    standard_days = RedmineSequentialTasks::StandardDays.new(@project.id) # the project's days, else the tracker's
    @tables = shown.map do |tracker|
      steps = settings.find { |s| s.tracker_id == tracker.id }.steps.sort_by(&:position)
      stages = steps.map { |step| stage_figures(step, rows.select { |r| r.tracker_id == tracker.id && r.status_id == step.status_id }) }
      stages.each { |s| s[:standard] = standard_days.days(tracker.id, s[:step]) }
      bottleneck = RedmineSequentialTasks::StageStats.bottleneck(
        stages.map { |s| { key: s[:step].id, median: s[:summary][:median], standard: s[:standard], count: s[:summary][:count] } }
      )
      { tracker: tracker, stages: stages, bottleneck: bottleneck }
    end
  end

  private

  # The figures of one stage from its visits (rows of StageHistory)
  def stage_figures(step, visits)
    done = visits.reject(&:ongoing)
    baseline = RedmineSequentialTasks::StageStats.baseline(done.map(&:dwell))
    ongoing = visits.select(&:ongoing)
    {
      step: step,
      summary: RedmineSequentialTasks::StageStats.summarize(done.map { |r| { dwell: r.dwell, plan: r.plan } }),
      enough: !baseline.nil?, # enough finished stays to say something
      now: ongoing.size,
      slow: ongoing.count { |r| RedmineSequentialTasks::StageStats.slowness(r.dwell, baseline) }
    }
  end
end
