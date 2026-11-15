# frozen_string_literal: true

module RedmineSequentialTasks
  class WorkingDayCalculator
    # How far ahead a working day is looked for: about half a year. With none in that time the plan cannot be
    # built, and creating or rescheduling an issue of a sequential tracker is refused instead of looping forever or
    # quietly counting every day (Redmine's setting may be changed by other plugins in ways not known here).
    SEARCH_DAYS = 183

    # The days of one stage: 1 to MAX_STAGE_DAYS (the same as the tracker settings), on the server too (review 2026-11-14:
    # a huge number would keep a request busy counting days, and a huge plan would make the timeline unusable)
    MAX_STAGE_DAYS = 365
    # A start or due date of a sequential issue must lie within this many years of today (same reason)
    DATE_RANGE_YEARS = 10

    def self.stage_days(value)
      days = Integer(value.to_s, 10, exception: false)
      days.nil? ? nil : days.clamp(1, MAX_STAGE_DAYS)
    end

    def self.date_in_range?(date, today = User.current.today)
      date.nil? || (today.prev_year(DATE_RANGE_YEARS)..today.next_year(DATE_RANGE_YEARS)).cover?(date)
    end

    # Raised when no working day is found within SEARCH_DAYS
    class NoWorkingDay < StandardError; end

    class << self
      # Return array of integers (1..7) representing non-working days
      # 1=Monday, ..., 6=Saturday, 7=Sunday (matches Date#cwday)
      def non_working_week_days
        (Setting.non_working_week_days || []).map(&:to_i)
      end

      # Is there a working day within SEARCH_DAYS from the date? (the plan can be built)
      def schedulable?(date = User.current.today)
        (0...SEARCH_DAYS).any? { |i| working_day?(date + i) }
      end

      # Check if a given date is a working day
      def working_day?(date)
        return false if date.nil?
        !non_working_week_days.include?(date.cwday)
      end

      # Advance to the date itself if it is a working day, or to the next working day (NoWorkingDay when there is none
      # within SEARCH_DAYS)
      def next_working_day(date)
        return nil if date.nil?

        SEARCH_DAYS.times do |i|
          cur = date + i
          return cur if working_day?(cur)
        end
        raise NoWorkingDay
      end

      # Calculate the end date for a given working days duration starting from start_date
      # If start_date is a non-working day, it is first shifted to the next working day.
      # duration_days = 1 means the stage starts and ends on start_date.
      def calculate_end_date(start_date, duration_days)
        return nil if start_date.nil?

        duration = [duration_days.to_i, 1].max
        cur = next_working_day(start_date)
        remaining = duration - 1

        while remaining > 0
          cur = next_working_day(cur + 1) # NoWorkingDay rather than an endless loop
          remaining -= 1
        end
        cur
      end

      # Calculate the start date of the next sequential stage following an end date
      # The next stage begins on the next working day after prev_end_date
      def next_stage_start_date(prev_end_date)
        return nil if prev_end_date.nil?
        next_working_day(prev_end_date + 1.day)
      end

      # Days of a stage from start_date to end_date (inclusive): working days, or every day when all_days
      def days_between(start_date, end_date, all_days = false)
        return working_days_between(start_date, end_date) unless all_days
        return 0 if start_date.nil? || end_date.nil? || start_date > end_date

        (end_date - start_date).to_i + 1
      end

      # The last day of a stage of duration_days starting on start_date (moved to a working day first, as every stage
      # starts on one): counted in working days, or in every day when all_days
      def end_date_for(start_date, duration_days, all_days = false)
        return calculate_end_date(start_date, duration_days) unless all_days
        return nil if start_date.nil?

        next_working_day(start_date) + ([duration_days.to_i, 1].max - 1)
      end

      # Count the number of working days between start_date and end_date (inclusive)
      def working_days_between(start_date, end_date)
        return 0 if start_date.nil? || end_date.nil? || start_date > end_date

        (start_date..end_date).count { |d| working_day?(d) }
      end
    end
  end
end
