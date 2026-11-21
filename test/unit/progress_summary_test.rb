# frozen_string_literal: true

# Standalone test (no Redmine test DB needed):
#   ruby test/unit/progress_summary_test.rb
require 'minitest/autorun'
require 'date'
require File.expand_path('../../lib/redmine_sequential_tasks/progress_summary', __dir__)

class ProgressSummaryTest < Minitest::Test
  Stage = Struct.new(:position, :status_id, :planned_start_date, :planned_end_date, :stage_status)
  FakeIssue = Struct.new(:status_id, :closed) do
    def closed?
      closed
    end
  end

  TODAY = Date.new(2026, 11, 4) # Wednesday

  # Three stages: 11/02-11/03, 11/04-11/05, 11/06-11/09 (status ids 10, 20, 30)
  def stages(overrides = {})
    [
      Stage.new(1, 10, Date.new(2026, 11, 2), Date.new(2026, 11, 3), overrides[1] || 'completed'),
      Stage.new(2, 20, Date.new(2026, 11, 4), Date.new(2026, 11, 5), overrides[2] || 'in_progress'),
      Stage.new(3, 30, Date.new(2026, 11, 6), Date.new(2026, 11, 9), overrides[3] || 'pending')
    ]
  end

  def summary(status_id, stage_list = stages, closed: false, today: TODAY)
    RedmineSequentialTasks::ProgressSummary.new(FakeIssue.new(status_id, closed), stage_list, today)
  end

  # the anchor of a change of the plan
  def test_the_anchor_is_the_current_stage
    assert_equal 2, summary(20).schedule_anchor.position
  end

  def test_a_status_without_a_stage_before_anything_started_is_anchored_at_the_first_stage
    list = stages(1 => 'pending', 2 => 'pending', 3 => 'pending')
    assert_nil summary(99, list).current_stage
    assert_equal 1, summary(99, list).schedule_anchor.position
  end

  def test_a_status_without_a_stage_after_a_stage_finished_has_no_anchor
    list = stages(1 => 'completed', 2 => 'pending', 3 => 'pending')
    assert_nil summary(99, list).schedule_anchor
  end

  def test_no_stages_no_anchor
    assert_nil summary(99, []).schedule_anchor
  end

  # on a weekend no stage covers today; the stage planned for the working day before holds
  def test_on_a_weekend_the_stage_of_the_friday_before_is_expected
    list = [
      Stage.new(1, 10, Date.new(2026, 11, 2), Date.new(2026, 11, 3), 'completed'),
      Stage.new(2, 20, Date.new(2026, 11, 4), Date.new(2026, 11, 6), 'completed'), # ends on Friday
      Stage.new(3, 30, Date.new(2026, 11, 9), Date.new(2026, 11, 10), 'in_progress')
    ]
    sunday = Date.new(2026, 11, 8)
    s = summary(30, list, today: sunday)
    assert_equal 20, s.expected_stage.status_id
    assert_equal :ahead, s.state
    assert_equal Date.new(2026, 11, 9), s.progress_date
    list[1].stage_status = 'in_progress'
    list[2].stage_status = 'pending'
    s = summary(20, list, today: sunday) # still in the stage that ended on Friday: behind, as on Monday
    assert_equal :delayed, s.state
    assert_equal 2, s.delay_days
  end

  def test_before_the_first_stage_nothing_is_expected
    s = summary(10, stages, today: Date.new(2026, 11, 1))
    assert_nil s.expected_stage
    assert_equal :pending, s.state
  end

  # before the start date, the first stage (in progress in the records) is not started on the screens
  def test_the_first_stage_before_the_start_date_is_not_started
    started = Struct.new(:position, :status_id, :planned_start_date, :planned_end_date, :stage_status, :actual_end_at)
    list = [started.new(1, 10, Date.new(2026, 11, 9), Date.new(2026, 11, 10), 'in_progress', nil),
            started.new(2, 20, Date.new(2026, 11, 11), Date.new(2026, 11, 12), 'pending', nil)]
    s = summary(10, list)
    assert_equal :pending, s.state
    assert s.not_started_stage?(list[0])
    refute s.not_started_stage?(list[1])
    refute summary(10, list, today: Date.new(2026, 11, 9)).not_started_stage?(list[0]) # the start date has come
  end

  def test_closed_issue_is_closed_even_when_stages_are_overdue
    s = summary(20, stages, closed: true, today: Date.new(2026, 12, 1))
    assert_equal :closed, s.state
    assert_equal 0, s.delay_days
    assert_equal Date.new(2026, 12, 1), s.progress_date
  end

  def test_on_schedule_is_in_progress
    s = summary(20)
    assert_equal :in_progress, s.state
    assert_equal 0, s.delay_days
    assert_equal TODAY, s.progress_date
    assert_equal 20, s.current_stage.status_id
    assert_equal 20, s.expected_stage.status_id
  end

  def test_past_planned_end_of_current_stage_is_delayed
    # stage 1 ended 11/03, the issue is still in stage 1 on 11/04 -> behind the expected stage 2
    s = summary(10)
    assert_equal :delayed, s.state
    assert_equal 1, s.delay_days
    assert_equal Date.new(2026, 11, 3), s.progress_date
  end

  def test_delay_days_counts_from_planned_end
    s = summary(10, stages, today: Date.new(2026, 11, 3) + 1) # same as above
    assert_equal 1, s.delay_days
    s = summary(20, stages, today: Date.new(2026, 11, 8))      # stage 2 ended 11/05, expected is stage 3
    assert_equal :delayed, s.state
    assert_equal 3, s.delay_days
    assert_equal Date.new(2026, 11, 5), s.progress_date
  end

  def test_all_stage_dates_passed_uses_last_stage_as_expected
    s = summary(30, stages, today: Date.new(2026, 11, 12))
    assert_equal 30, s.expected_stage.status_id
    assert_equal :delayed, s.state
    assert_equal 3, s.delay_days
  end

  def test_delay_is_at_least_one_day_when_behind_expected_stage
    list = stages
    list[0].planned_end_date = nil
    s = summary(10, list)
    assert_equal :delayed, s.state
    assert_equal 1, s.delay_days
    assert_equal TODAY - 1, s.progress_date
  end

  def test_future_first_stage_start_is_pending_even_if_stage_status_says_in_progress
    s = summary(10, stages('1' => 'in_progress'), today: Date.new(2026, 11, 1))
    assert_equal :pending, s.state
    assert_nil s.expected_stage
  end

  def test_ahead_of_schedule
    s = summary(30, stages) # today is in stage 2, the issue is already in stage 3
    assert_equal :ahead, s.state
    assert_equal Date.new(2026, 11, 6), s.progress_date
  end

  def test_status_without_a_stage_and_no_stage_in_progress_has_no_current_stage
    # (the in-progress fallback for statuses outside the stages is tested below)
    s = summary(99, stages(2 => 'completed'))
    assert_nil s.current_stage
    assert_equal :in_progress, s.state
    assert_equal TODAY, s.progress_date
  end

  def test_all_stages_completed_but_not_closed_is_not_closed
    s = summary(99, stages(1 => 'completed', 2 => 'completed', 3 => 'completed'), today: Date.new(2026, 11, 20))
    assert_equal :in_progress, s.state
  end

  def test_no_stages_is_in_progress
    s = summary(10, [])
    assert_equal :in_progress, s.state
    assert_equal 0, s.delay_days
  end

  def test_current_stage_is_decided_by_issue_status_not_stage_status
    # the stage for the issue's status is still 'pending' (drifted data): the state does not change
    s = summary(20, stages(2 => 'pending'))
    assert_equal :in_progress, s.state
    assert_equal 20, s.current_stage.status_id
  end

  def test_in_a_gap_between_stages_the_stage_before_is_expected
    # Saturday 11/07 is not inside any planned stage when stage 2 starts on Monday: stage 1 holds
    list = [
      Stage.new(1, 10, Date.new(2026, 11, 2), Date.new(2026, 11, 6), 'completed'),
      Stage.new(2, 20, Date.new(2026, 11, 9), Date.new(2026, 11, 10), 'pending')
    ]
    saturday = Date.new(2026, 11, 7)
    s = summary(20, list, today: saturday)
    assert_equal 10, s.expected_stage.status_id
    assert_equal :ahead, s.state # in Monday's stage already, as it would be on Friday
    s = summary(10, list, today: saturday)
    assert_equal :delayed, s.state     # past the planned end of its own stage
    assert_equal 1, s.delay_days
  end

  def test_delayed_has_priority_over_ahead_and_pending
    # an issue past the planned end of its current stage is delayed, not in_progress
    s = summary(20, stages, today: Date.new(2026, 11, 6))
    assert_equal :delayed, s.state
  end

  # --- Statuses without a stage: the last in-progress stage stays the current one

  def test_out_of_stage_status_uses_the_in_progress_stage_as_current
    s = summary(99, stages) # stage 2 is in progress, the issue sits in a status with no stage
    assert s.out_of_stage?
    assert_equal 20, s.current_stage.status_id
    assert_equal :in_progress, s.state
  end

  def test_out_of_stage_status_still_counts_the_delay
    s = summary(99, stages, today: Date.new(2026, 11, 8)) # stage 2 ended 11/05
    assert_equal :delayed, s.state
    assert_equal 3, s.delay_days
    assert s.out_of_stage?
  end

  def test_out_of_stage_without_any_in_progress_stage_has_no_current_stage
    s = summary(99, stages(1 => 'completed', 2 => 'completed', 3 => 'completed'))
    assert s.out_of_stage?
    assert_nil s.current_stage
  end

  def test_in_stage_and_closed_issues_are_not_out_of_stage
    assert !summary(20).out_of_stage?
    assert !summary(99, stages, closed: true).out_of_stage?
    assert !summary(10, []).out_of_stage?
  end

  def test_skipped_stages_are_never_the_fallback_current_stage
    s = summary(99, stages(1 => 'skipped', 2 => 'skipped', 3 => 'skipped'))
    assert_nil s.current_stage
  end

  # --- the projected end of the issue

  def test_the_projected_end_is_the_planned_end_of_the_last_stage_when_on_schedule
    assert_equal Date.new(2026, 11, 9), summary(20).projected_end
  end

  def test_the_projected_end_is_pushed_back_by_the_delay
    s = summary(10) # still in stage 1, the day after it ended: one day behind
    assert_equal 1, s.delay_days
    assert_equal Date.new(2026, 11, 10), s.projected_end
  end

  def test_the_projected_end_ignores_skipped_stages
    s = summary(20, stages(3 => 'skipped'))
    assert_equal Date.new(2026, 11, 5), s.projected_end
  end

  def test_a_closed_issue_has_no_projected_end
    assert_nil summary(20, stages, closed: true).projected_end
  end

  def test_an_issue_without_stages_has_no_projected_end
    assert_nil summary(20, []).projected_end
  end
end
