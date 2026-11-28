# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The plan of a new issue: the standard days, or the days chosen on the new issue form, and a due date given by hand.
class CreationPlanTest < ActiveSupport::TestCase
  MONDAY = Date.new(2026, 11, 30)

  def setup
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
  end

  def steps(*days)
    days.each_with_index { |d, i| @setting.steps.create!(status_id: [1, 2, 3][i], position: i + 1, default_duration_days: d) }
  end

  def plan(override = nil)
    RedmineSequentialTasks::CreationPlan.new(@setting.reload, 1, override)
  end

  def spans(entries)
    entries.map { |e| [e.start_date, e.end_date] }
  end

  def test_the_standard_days_one_stage_after_another_on_working_days
    steps(2, 3)
    assert_equal [[MONDAY, MONDAY + 1], [MONDAY + 2, MONDAY + 4]], spans(plan.entries(MONDAY))
  end

  def test_a_start_on_a_weekend_moves_to_the_monday
    steps(1)
    assert_equal [[MONDAY, MONDAY]], spans(plan.entries(MONDAY - 2))
  end

  def test_the_days_chosen_on_the_form_replace_the_standard_days
    steps(2, 3)
    entries = plan(1 => { days: '4', all: false }).entries(MONDAY)
    assert_equal [4, 3], entries.map(&:days)
    assert_equal [[MONDAY, MONDAY + 3], [MONDAY + 4, MONDAY + 8]], spans(entries), 'the second stage goes over the weekend'
  end

  def test_a_stage_that_counts_every_day_runs_over_the_weekend
    steps(2, 3)
    entries = plan(1 => { days: '3', all: true }).entries(MONDAY + 3) # Thursday
    assert_equal [MONDAY + 3, MONDAY + 5], [entries.first.start_date, entries.first.end_date], 'Thursday to Saturday'
    assert entries.first.all_days
    assert_equal MONDAY + 7, entries.last.start_date, 'the next stage starts on the next working day'
  end

  def test_days_out_of_range_are_kept_within_one_to_365_and_rubbish_is_the_standard
    steps(2, 3)
    entries = plan(1 => { days: '0' }, 2 => { days: 'abc' }).entries(MONDAY)
    assert_equal [1, 3], entries.map(&:days)
    assert_equal 365, plan(1 => { days: '9999' }).entries(MONDAY).first.days
  end

  def test_the_zero_day_wait_takes_no_days_even_when_some_are_sent
    steps(0, 2)
    entries = plan(1 => { days: '5' }).entries(MONDAY)
    assert entries.first.zero_day
    assert_equal [MONDAY, MONDAY], [entries.first.start_date, entries.first.end_date]
    assert_equal [MONDAY, MONDAY + 1], [entries.last.start_date, entries.last.end_date]
  end

  def test_a_due_date_given_makes_the_last_stage_end_on_it
    steps(2, 3)
    entries = plan.entries(MONDAY, due: MONDAY + 9) # the next Wednesday
    assert_equal MONDAY + 9, entries.last.end_date
    assert_equal 6, entries.last.days
    assert_equal MONDAY + 1, entries.first.end_date, 'the stages before it keep their days'
  end

  def test_a_due_date_on_a_weekend_ends_the_plan_on_the_friday_before
    steps(2, 3)
    assert_equal MONDAY + 11, plan.end_date(MONDAY, due: MONDAY + 12) # Sunday -> Friday
  end

  def test_a_due_date_that_leaves_the_last_stage_no_day_does_not_fit
    steps(2, 3)
    assert_raises(RedmineSequentialTasks::CreationPlan::CannotFit) { plan.entries(MONDAY, due: MONDAY + 1) }
  end
end
