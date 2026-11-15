# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Rules under test (completed stages are fixed, the current stage keeps its start)
class StageReschedulerTest < ActiveSupport::TestCase
  Stage = Struct.new(:id, :position, :planned_start_date, :planned_end_date, :stage_status)

  def setup
    Setting.non_working_week_days = %w[6 7] # Saturday, Sunday
  end

  # 11/02 Mon .. 11/03 Tue (completed), 11/04 Wed .. 11/05 Thu (current), 11/06 Fri .. 11/09 Mon (pending)
  def stages
    [
      Stage.new(1, 1, Date.new(2026, 11, 2), Date.new(2026, 11, 3), 'completed'),
      Stage.new(2, 2, Date.new(2026, 11, 4), Date.new(2026, 11, 5), 'in_progress'),
      Stage.new(3, 3, Date.new(2026, 11, 6), Date.new(2026, 11, 9), 'pending')
    ]
  end

  def rescheduler(list = stages, anchor_position = 2)
    anchor = list.find { |s| s.position == anchor_position }
    RedmineSequentialTasks::StageRescheduler.new(list, anchor)
  end

  def test_only_the_current_and_later_stages_are_adjustable
    r = rescheduler
    assert !r.adjustable?(stages[0])
    assert r.adjustable?(stages[1])
    assert r.adjustable?(stages[2])
    assert r.adjustable_any?
  end

  def test_without_changes_the_current_dates_are_kept
    result = rescheduler.call({})
    assert_equal [2, 3], result.map { |sc| sc.stage.id }
    assert_equal [Date.new(2026, 11, 4), Date.new(2026, 11, 6)], result.map(&:start_date)
    assert_equal [Date.new(2026, 11, 5), Date.new(2026, 11, 9)], result.map(&:end_date)
  end

  def test_lengthening_the_current_stage_slides_the_later_ones_over_the_weekend
    # 4 working days from Wed 11/04: Wed, Thu, Fri, Mon -> ends Mon 11/09; stage 3 (2 working days) starts Tue 11/10
    result = rescheduler.call(2 => 4)
    assert_equal Date.new(2026, 11, 4), result[0].start_date, 'the current stage keeps its start'
    assert_equal Date.new(2026, 11, 9), result[0].end_date
    assert_equal Date.new(2026, 11, 10), result[1].start_date
    assert_equal Date.new(2026, 11, 11), result[1].end_date
  end

  def test_durations_for_fixed_stages_are_ignored
    result = rescheduler.call(1 => 30, 2 => 2)
    assert_equal [2, 3], result.map { |sc| sc.stage.id }
    assert_equal Date.new(2026, 11, 5), result[0].end_date
  end

  def test_invalid_durations_become_one_day
    result = rescheduler.call(2 => 0)
    assert_equal Date.new(2026, 11, 4), result[0].end_date
  end

  def test_nothing_is_adjustable_without_a_current_stage
    r = RedmineSequentialTasks::StageRescheduler.new(stages, nil)
    assert !r.adjustable_any?
    assert !r.adjustable?(stages[2])
    assert_equal [], r.call(2 => 3)
  end

  # keep the due date fixed, change the split between the adjustable stages instead
  def test_call_fixed_shrinks_a_later_untouched_stage_to_keep_the_due_date
    # stage 2 (current) is 2 days (11/04-11/05), stage 3 is 2 days (11/06,11/09): total 4, due 11/09
    result = rescheduler.call_fixed({ 2 => 3 }) # +1 day on stage 2
    assert_equal [3, 1], result.map(&:duration), 'stage 3 gives back the day stage 2 took'
    assert_equal Date.new(2026, 11, 9), result.last.end_date, 'the due date does not move'
  end

  def test_call_fixed_grows_a_later_untouched_stage_when_a_stage_is_shortened
    result = rescheduler.call_fixed({ 2 => 1 }) # -1 day on stage 2
    assert_equal [1, 3], result.map(&:duration), 'stage 3 grows to fill the day stage 2 gave up'
    assert_equal Date.new(2026, 11, 9), result.last.end_date
  end

  def test_call_fixed_refuses_when_there_is_no_room_to_shrink_into
    assert_raises(RedmineSequentialTasks::StageRescheduler::CannotFit) { rescheduler.call_fixed({ 2 => 4 }) }
  end

  def test_call_fixed_with_an_explicit_target_end_moves_the_due_date_there
    # no explicit per-stage days: the last untouched stage absorbs the two extra days
    result = rescheduler.call_fixed({}, target_end: Date.new(2026, 11, 11))
    assert_equal [2, 4], result.map(&:duration)
    assert_equal Date.new(2026, 11, 11), result.last.end_date
  end

  def test_call_fixed_with_an_explicit_target_end_refuses_when_it_does_not_fit
    assert_raises(RedmineSequentialTasks::StageRescheduler::CannotFit) { rescheduler.call_fixed({}, target_end: Date.new(2026, 11, 5)) }
  end

  # a stage that counts the non-working days too
  AllDaysStage = Struct.new(:id, :position, :planned_start_date, :planned_end_date, :stage_status, :count_non_working) do
    def all_days? = count_non_working
  end

  def test_a_stage_that_counts_every_day_runs_over_the_weekend
    list = [AllDaysStage.new(2, 2, Date.new(2026, 11, 4), Date.new(2026, 11, 5), 'in_progress', true),
            AllDaysStage.new(3, 3, Date.new(2026, 11, 6), Date.new(2026, 11, 9), 'pending', false)]
    r = RedmineSequentialTasks::StageRescheduler.new(list, list.first)
    result = r.call({ 2 => 4 }) # Wed, Thu, Fri, Sat
    assert_equal Date.new(2026, 11, 7), result.first.end_date
    assert_equal Date.new(2026, 11, 9), result.last.start_date, 'the next stage starts on the next working day (Mon)'
    assert_equal 2, r.current_duration(list.first), 'its days are counted the same way: Wed and Thu'
  end

  def test_call_fixed_keeps_the_due_date_when_the_slack_counts_every_day
    list = [AllDaysStage.new(2, 2, Date.new(2026, 11, 4), Date.new(2026, 11, 5), 'in_progress', false),
            AllDaysStage.new(3, 3, Date.new(2026, 11, 6), Date.new(2026, 11, 9), 'pending', true)]
    r = RedmineSequentialTasks::StageRescheduler.new(list, list.first)
    result = r.call_fixed({ 2 => 3 }) # stage 2 ends Fri; the slack then runs Mon..Mon = 1 day
    assert_equal Date.new(2026, 11, 9), result.last.end_date, 'the due date stays'
    assert_equal 1, result.last.duration
  end

  def test_a_current_stage_without_dates_starts_on_the_next_working_day_of_today
    list = stages
    list[1].planned_start_date = nil
    list[1].planned_end_date = nil
    result = rescheduler(list).call(2 => 1)
    expected = RedmineSequentialTasks::WorkingDayCalculator.next_working_day(User.current.today)
    assert_equal expected, result[0].start_date
  end
end
