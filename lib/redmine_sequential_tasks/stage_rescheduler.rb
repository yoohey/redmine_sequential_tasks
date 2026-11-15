# frozen_string_literal: true

module RedmineSequentialTasks
  # Recalculates the planned dates of an issue's stages when their durations are adjusted.
  # Rule: stages before the current stage are fixed (their planned dates and the
  # actual-vs-plan difference stay as they are); the current stage keeps its planned start date; the stages
  # after it slide over working days.
  #
  # stages - the issue's stages (id, position, planned_start_date, planned_end_date)
  # anchor - the current stage (see ProgressSummary#current_stage), or nil when nothing can be adjusted
  #          (closed issue, or no stage in progress)
  class StageRescheduler
    Schedule = Struct.new(:stage, :duration, :start_date, :end_date)

    # Raised by call_fixed when there is no room left to shrink into the target
    class CannotFit < StandardError; end

    def initialize(stages, anchor)
      @stages = stages.sort_by(&:position)
      @anchor = anchor
    end

    def adjustable_any?
      !@anchor.nil?
    end

    # The one rule for moving the start date (used by the adjustment screen, the project timeline and
    # a direct edit of the issue's start date): the issue is open (an anchor was given), no stage has finished or
    # was skipped, and the current stage is the first real one (only a 0-day wait may stand before it). Then
    # nothing whose plan-vs-actual is settled would move, and the plan really begins where the start date is.
    def start_changeable?
      return false unless adjustable_any?
      return false if @stages.any? { |s| s.actual_end_at.present? || s.stage_status == 'skipped' }

      @stages.all? { |s| s.position >= @anchor.position || zero_day?(s) }
    end

    def adjustable?(stage)
      !@anchor.nil? && stage.position >= @anchor.position && !zero_day?(stage) # a wait has no days to adjust
    end

    def zero_day?(stage)
      stage.respond_to?(:zero_day) && stage.zero_day ? true : false
    end

    # Days between the planned start and end of a stage (working days, or every day for a stage that counts the
    # non-working days too), or nil without dates
    def current_duration(stage)
      return nil unless stage.planned_start_date && stage.planned_end_date

      WorkingDayCalculator.days_between(stage.planned_start_date, stage.planned_end_date, all_days?(stage))
    end

    def all_days?(stage)
      stage.respond_to?(:all_days?) && stage.all_days?
    end

    # durations - { stage id => working days }; stages without an entry keep their current duration.
    # Returns one Schedule per adjustable stage, in order. The due date moves freely with the total.
    # start_date - a new start for the first adjustable stage (only when start_changeable?), else nil.
    #              Positional, so that call(stage_id => days) keeps reading its braceless hash as durations.
    def call(durations, start_date = nil)
      return [] unless adjustable_any?

      stages = @stages.select { |s| adjustable?(s) }
      build(stages, nominal_durations(stages, durations), start_date)
    end

    # Like call, but keeps the due date at target_end — the current end of the last adjustable stage when nil.
    # The room is measured in dates, not in a sum of days, since a stage may count every day. The
    # LAST adjustable stage (the one right before the due date) is the slack: its own entry in durations is never
    # read; it gets the days from the next working day after the others up to target_end, counted its own way.
    # With a single adjustable stage and a target_end (a direct edit of the due date), that stage is the slack
    # itself and its end moves to target_end. Raises CannotFit when the slack would have less than 1 day.
    def call_fixed(durations, target_end: nil, start_date: nil)
      return [] unless adjustable_any?

      stages = @stages.select { |s| adjustable?(s) }
      return [] if stages.empty?
      return call(durations, start_date) if stages.size == 1 && target_end.nil? # nothing to keep it against
      return [fit_single(stages.first, target_end, start_date)] if stages.size == 1

      slack = stages.last
      others = stages[0..-2]
      nominal = nominal_durations(others, durations)
      target = target_end || slack.planned_end_date
      laid = build(others, nominal, start_date)
      slack_start = WorkingDayCalculator.next_stage_start_date(laid.last.end_date)
      slack_duration = target ? WorkingDayCalculator.days_between(slack_start, target, all_days?(slack)) : 0
      raise CannotFit if slack_duration < 1

      nominal[slack.id] = slack_duration
      build(stages, nominal, start_date)
    end

    private

    # The only adjustable stage, ending on target_end (a direct edit of the due date on the last stage)
    def fit_single(stage, target_end, start_date)
      first = WorkingDayCalculator.next_working_day(start_date || @anchor.planned_start_date || User.current.today)
      days = WorkingDayCalculator.days_between(first, target_end, all_days?(stage))
      raise CannotFit if days < 1

      Schedule.new(stage, days, first, WorkingDayCalculator.end_date_for(first, days, all_days?(stage)))
    end

    def nominal_durations(stages, durations)
      stages.to_h do |s|
        given = durations.key?(s.id) ? WorkingDayCalculator.stage_days(durations[s.id]) : nil # 1..365, nil if unreadable
        [s.id, given || current_duration(s) || 1]
      end
    end

    def build(stages, nominal, start_date = nil)
      cur_start = WorkingDayCalculator.next_working_day(start_date || @anchor.planned_start_date || User.current.today)
      stages.map do |stage|
        duration = nominal[stage.id]
        stage_start = cur_start
        stage_end = WorkingDayCalculator.end_date_for(stage_start, duration, all_days?(stage))
        cur_start = WorkingDayCalculator.next_stage_start_date(stage_end)
        Schedule.new(stage, duration, stage_start, stage_end)
      end
    end
  end
end
