# frozen_string_literal: true

require 'date'

module RedmineSequentialTasks
  # Overall progress state of one issue, shared by the timeline, matrix and issue detail screens.
  # Depends only on Date, so it can be tested without Redmine.
  #
  # issue  - responds to #status_id and #closed?
  # stages - issue stages (position, status_id, planned_start_date, planned_end_date), in any order
  # today  - Date
  class ProgressSummary
    attr_reader :current_stage, :expected_stage

    def initialize(issue, stages, today)
      @issue = issue
      @stages = stages.sort_by(&:position)
      @today = today

      # The current stage is decided by the Redmine status, not by IssueStage#stage_status.
      # For a status without a stage (e.g. Feedback), the last stage still in progress stays the
      # current one: it marks how far the issue got.
      @current_stage = @stages.find { |s| s.status_id == issue.status_id }
      @current_stage ||= @stages.select { |s| s.stage_status == 'in_progress' }.last
      @expected_stage = find_expected_stage
      @delay_days = compute_delay_days
    end

    # :closed, :delayed, :pending, :ahead or :in_progress (checked in this order)
    def state
      return :closed if closed?
      return :delayed if delayed?
      return :pending if pending?
      return :ahead if ahead?

      :in_progress
    end

    # The first stage of an issue whose start date is still ahead (pending?). In the records it is in progress: the
    # issue has been in that status since it was created. On the screens nothing has started yet, so it is shown as
    # planned, without its actual start
    def not_started_stage?(stage)
      pending? && !stage.nil? && stage == @stages.first && stage.stage_status == 'in_progress' && stage.actual_end_at.nil?
    end

    # The issue status has no stage of its own (and the issue is open): the screens flag it
    def out_of_stage?
      !closed? && !@stages.empty? && @stages.none? { |s| s.status_id == @issue.status_id }
    end

    # Only Redmine's closed statuses count as closed, even if every stage is completed
    def closed?
      @issue.closed? ? true : false
    end

    def delayed?
      !closed? && @delay_days > 0
    end

    # The first stage is planned to start after today
    def pending?
      first = @stages.first
      !first.nil? && !first.planned_start_date.nil? && @today < first.planned_start_date
    end

    # The issue is at a later stage than the one planned for today
    def ahead?
      !closed? && !delayed? && !@expected_stage.nil? && !@current_stage.nil? &&
        @current_stage.position > @expected_stage.position
    end

    # Days past the planned end of the current stage (at least 1 when behind), 0 when not delayed
    def delay_days
      delayed? ? @delay_days : 0
    end

    # When the issue is expected to be done: the end of the last stage that is not skipped, pushed back by the delay
    # (calendar days; a guide, not an exact rescheduling). nil when finished or without stages
    def projected_end
      return nil if closed?

      last_end = @stages.reject { |s| s.stage_status == 'skipped' }.filter_map(&:planned_end_date).max
      last_end && (last_end + delay_days)
    end

    # Position of the issue on the lightning line
    def progress_date
      if closed?
        @today
      elsif delayed?
        # Delayed: the progress point lags behind at the end date of the stuck stage
        @current_stage&.planned_end_date || (@today - @delay_days)
      elsif ahead?
        @current_stage.planned_start_date || @today
      else
        @today
      end
    end

    private

    # 1. The stage covering today.
    # 2. Else the last stage planned to end before today: on a non-working day (a weekend) no stage covers today, and
    #    the stage planned for the working day before still holds. This also gives the last stage when every
    #    stage is over. nil before the first stage starts.
    def find_expected_stage
      covering = @stages.find do |s|
        s.planned_start_date && s.planned_end_date && (s.planned_start_date..s.planned_end_date).cover?(@today)
      end
      return covering if covering

      @stages.select { |s| s.planned_end_date && s.planned_end_date < @today }.max_by(&:planned_end_date)
    end

    def compute_delay_days
      return 0 if @current_stage.nil?

      days = 0
      if @expected_stage && @current_stage.position < @expected_stage.position
        days = (@today - (@current_stage.planned_end_date || @today)).to_i
        behind = true
      elsif @current_stage.planned_end_date && @today > @current_stage.planned_end_date
        days = (@today - @current_stage.planned_end_date).to_i
        behind = true
      end
      behind ? [days, 1].max : 0
    end
  end
end
