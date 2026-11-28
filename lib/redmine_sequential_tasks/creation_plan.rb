# frozen_string_literal: true

module RedmineSequentialTasks
  # The plan of a new issue: its stages laid out one after another from the start, with the standard days (the
  # project's, else the tracker's) or with the days chosen on the new issue form. Used for the due date before the
  # issue is created and for the stages written after it.
  class CreationPlan
    class CannotFit < StandardError; end

    Entry = Struct.new(:step, :start_date, :end_date, :days, :all_days, :zero_day, keyword_init: true)

    # setting  - the SequentialTaskSetting of the tracker
    # override - { status_id => { days: n, all: bool } } from the form, or nil (the standard days)
    def initialize(setting, project_id, override = nil)
      @setting = setting
      @standard = StandardDays.new(project_id)
      @override = override || {}
    end

    # The entries from `start` (moved to a working day). With `due`, the last stage that has days ends on it
    # (CannotFit when it would get less than one day).
    def entries(start, due: nil)
      calc = WorkingDayCalculator
      cur = calc.next_working_day(start)
      list = @setting.steps.each_with_index.map do |step, index|
        standard = @standard.days(@setting.tracker_id, step).to_i
        if index.zero? && standard <= 0 # a wait for somebody to pick the issue up: a point, no days
          Entry.new(step: step, start_date: cur, end_date: cur, days: 0, all_days: false, zero_day: true)
        else
          chosen = @override[step.status_id] || {}
          days = WorkingDayCalculator.stage_days(chosen[:days]) || [standard, 1].max
          all = chosen[:all] ? true : false
          first = calc.next_working_day(cur)
          last = calc.end_date_for(first, days, all)
          cur = calc.next_stage_start_date(last)
          Entry.new(step: step, start_date: first, end_date: last, days: days, all_days: all, zero_day: false)
        end
      end
      fit_to_due(list, due) if due
      list
    end

    def end_date(start, due: nil)
      entries(start, due: due).last&.end_date
    end

    private

    def fit_to_due(list, due)
      slack = list.reverse.find { |e| !e.zero_day }
      return unless slack && slack.end_date != due

      days = WorkingDayCalculator.days_between(slack.start_date, due, slack.all_days)
      raise CannotFit if days < 1

      slack.days = days
      slack.end_date = WorkingDayCalculator.end_date_for(slack.start_date, days, slack.all_days)
    end
  end
end
