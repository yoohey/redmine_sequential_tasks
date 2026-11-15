# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

class WorkingDayCalculatorTest < ActiveSupport::TestCase
  def setup
    # 6=Saturday, 7=Sunday
    Setting.non_working_week_days = ['6', '7']
  end

  def test_working_day
    # 2026-10-30 is Friday (cwday=5)
    # 2026-10-31 is Saturday (cwday=6)
    # 2026-11-01 is Sunday (cwday=7)
    # 2026-11-02 is Monday (cwday=1)
    friday = Date.new(2026, 10, 30)
    saturday = Date.new(2026, 10, 31)
    sunday = Date.new(2026, 11, 1)
    monday = Date.new(2026, 11, 2)

    assert RedmineSequentialTasks::WorkingDayCalculator.working_day?(friday)
    assert_not RedmineSequentialTasks::WorkingDayCalculator.working_day?(saturday)
    assert_not RedmineSequentialTasks::WorkingDayCalculator.working_day?(sunday)
    assert RedmineSequentialTasks::WorkingDayCalculator.working_day?(monday)
  end

  def test_next_working_day
    saturday = Date.new(2026, 10, 31)
    sunday = Date.new(2026, 11, 1)
    monday = Date.new(2026, 11, 2)

    assert_equal monday, RedmineSequentialTasks::WorkingDayCalculator.next_working_day(saturday)
    assert_equal monday, RedmineSequentialTasks::WorkingDayCalculator.next_working_day(sunday)
    assert_equal monday, RedmineSequentialTasks::WorkingDayCalculator.next_working_day(monday)
  end

  def test_calculate_end_date_skipping_weekend
    friday = Date.new(2026, 10, 30)
    monday = Date.new(2026, 11, 2)
    tuesday = Date.new(2026, 11, 3)

    # 1 working day starting Friday -> ends on Friday
    assert_equal friday, RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(friday, 1)

    # 2 working days starting Friday -> Friday + Monday -> ends on Monday
    assert_equal monday, RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(friday, 2)

    # 3 working days starting Friday -> Friday + Monday + Tuesday -> ends on Tuesday
    assert_equal tuesday, RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(friday, 3)
  end

  def test_calculate_end_date_starting_on_weekend
    saturday = Date.new(2026, 10, 31)
    monday = Date.new(2026, 11, 2)
    tuesday = Date.new(2026, 11, 3)

    # Starting on Saturday automatically shifts to Monday
    # 1 working day -> Monday
    assert_equal monday, RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(saturday, 1)
    # 2 working days -> Tuesday
    assert_equal tuesday, RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(saturday, 2)
  end

  def test_next_stage_start_date
    friday = Date.new(2026, 10, 30)
    monday = Date.new(2026, 11, 2)
    wednesday = Date.new(2026, 11, 4)
    thursday = Date.new(2026, 11, 5)

    # Stage ends on Friday -> next stage starts on Monday
    assert_equal monday, RedmineSequentialTasks::WorkingDayCalculator.next_stage_start_date(friday)

    # Stage ends on Wednesday -> next stage starts on Thursday
    assert_equal thursday, RedmineSequentialTasks::WorkingDayCalculator.next_stage_start_date(wednesday)
  end

  def test_working_days_between
    friday = Date.new(2026, 10, 30)
    monday = Date.new(2026, 11, 2)
    tuesday = Date.new(2026, 11, 3)

    # Friday to Monday has 2 working days (Friday, Monday)
    assert_equal 2, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(friday, monday)
    # Friday to Tuesday has 3 working days (Friday, Monday, Tuesday)
    assert_equal 3, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(friday, tuesday)
    # Friday to Friday has 1 working day
    assert_equal 1, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(friday, friday)
    # Saturday to Sunday has 0 working days
    assert_equal 0, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(Date.new(2026, 10, 31), Date.new(2026, 11, 1))
  end

  # no working day within half a year: the plan cannot be built (it used to loop forever)
  def test_without_any_working_day_the_plan_cannot_be_built
    calc = RedmineSequentialTasks::WorkingDayCalculator
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    monday = Date.new(2026, 11, 2)
    refute calc.schedulable?(monday)
    assert_raises(calc::NoWorkingDay) { calc.next_working_day(monday) }
    assert_raises(calc::NoWorkingDay) { calc.calculate_end_date(monday, 3) }
    assert_equal 0, calc.working_days_between(monday, monday + 6)

    Setting.non_working_week_days = %w[6 7]
    assert calc.schedulable?(monday)
  end
end
