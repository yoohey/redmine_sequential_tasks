# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# editing the issue's own start date or due date directly (not via the adjustment screen) reflows the
# stages. Redmine fixtures: statuses 1 New, 2 Assigned, 3 Resolved, 5 Closed.
class SequentialDateReflowTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :roles, :enumerations, :enabled_modules, :projects_trackers,
           :workflows, :members, :member_roles

  def setup
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| @setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    User.current = User.find(2)
  end

  def stages(issue)
    issue.issue_stages.reload.order(:position)
  end

  # ---- editing start_date, nothing started yet ------------------------------------------------

  def test_editing_the_start_date_before_anything_started_moves_the_whole_plan_and_keeps_each_durations
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2)) # Monday
    before = stages(issue).map { |s| RedmineSequentialTasks::WorkingDayCalculator.working_days_between(s.planned_start_date, s.planned_end_date) }

    issue.update!(start_date: Date.new(2026, 11, 9)) # a week later, also a Monday

    after = stages(issue)
    assert_equal before, after.map { |s| RedmineSequentialTasks::WorkingDayCalculator.working_days_between(s.planned_start_date, s.planned_end_date) }
    assert_equal Date.new(2026, 11, 9), after.first.planned_start_date
    assert_equal Date.new(2026, 11, 19), issue.reload.due_date, 'the due date follows the reflowed plan'
  end

  def test_editing_the_start_date_does_not_touch_the_real_entry_time_of_a_zero_day_stage
    @setting.steps.find_by(status_id: 1).update!(default_duration_days: 0)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    real_entry = stages(issue).first.actual_start_at

    issue.update!(start_date: Date.new(2026, 11, 9))

    assert_equal real_entry, stages(issue).first.reload.actual_start_at, 'the plan moved, but the real history did not'
    assert_equal Date.new(2026, 11, 9), stages(issue).first.planned_start_date
  end

  def test_nothing_moves_once_a_stage_has_finished
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    issue.init_journal(User.current)
    issue.status_id = 2 # stage 1 finishes
    issue.save!
    before = stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }

    issue.update!(start_date: Date.new(2026, 11, 9))

    assert_equal before, stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }, 'too late: something already happened'
  end

  # ---- editing due_date directly ----------------------------------------------------------------

  def test_editing_the_due_date_shrinks_the_last_adjustable_stage_to_fit
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2, start_date: Date.new(2026, 11, 2)) # stage 2 current
    due_before = issue.due_date

    issue.update!(due_date: due_before - 2) # two working days earlier (no weekend in between here)

    assert_equal due_before - 2, issue.reload.due_date
    assert_equal 1, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(stages(issue).last.planned_start_date, stages(issue).last.planned_end_date)
  end

  def test_editing_the_due_date_to_something_impossible_is_refused
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2, start_date: Date.new(2026, 11, 2))
    before = stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }

    issue.due_date = Date.new(2026, 11, 4) # far too soon: stage 2 alone already needs more than this
    assert_not issue.save
    assert issue.errors[:due_date].present?
    assert_equal before, stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }, 'refused before anything was written'
  end

  def test_clearing_the_due_date_is_not_refused
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2, start_date: Date.new(2026, 11, 2))
    assert issue.update(due_date: nil)
  end

  # The zero-day wait itself is never adjustable, but the real stages after it are, even while still
  # waiting: only the last one (the slack, right before the due date) is the one that actually moves.
  def test_the_due_date_reflow_leaves_the_zero_day_wait_alone_but_can_still_grow_the_last_stage
    @setting.steps.find_by(status_id: 1).update!(default_duration_days: 0)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    wait = stages(issue).find { |s| s.position == 1 }
    middle = stages(issue).find { |s| s.position == 2 }
    wait_before = [wait.planned_start_date, wait.planned_end_date]
    middle_before = [middle.planned_start_date, middle.planned_end_date]

    issue.update!(due_date: issue.due_date + 2) # 2 more working days, no weekend in the way

    assert_equal wait_before, [stages(issue).find { |s| s.position == 1 }.planned_start_date, stages(issue).find { |s| s.position == 1 }.planned_end_date],
                 'the wait itself is never touched'
    assert_equal middle_before, [stages(issue).find { |s| s.position == 2 }.planned_start_date, stages(issue).find { |s| s.position == 2 }.planned_end_date],
                 'only the last stage is the slack'
    last = stages(issue).find { |s| s.position == 3 }
    assert_equal 5, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(last.planned_start_date, last.planned_end_date)
  end

  # ---- one plan for both dates (review 2026-11-14) ---------------------------------------------

  def days(stage)
    RedmineSequentialTasks::WorkingDayCalculator.days_between(stage.planned_start_date, stage.planned_end_date, stage.all_days?)
  end

  # Both dates in one save (the issue form, the REST API, or Redmine moving the issue for a preceding one)
  def test_moving_both_dates_in_one_save_plans_from_the_new_start_up_to_the_new_due_date
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2)) # 3/3/3, due 11/12
    issue.update!(start_date: Date.new(2026, 11, 9), due_date: Date.new(2026, 11, 20))

    list = stages(issue).to_a
    assert_equal Date.new(2026, 11, 9), list.first.planned_start_date, 'the plan starts on the new start date'
    assert_equal [3, 3], [days(list[0]), days(list[1])], 'the first stages keep their days'
    assert_equal Date.new(2026, 11, 20), list.last.planned_end_date, 'the last stage ends on the new due date'
    assert_equal Date.new(2026, 11, 20), issue.reload.due_date
  end

  def test_a_preceding_issue_moving_this_one_keeps_the_plan_in_one_piece
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    issue.reload.reschedule_on!(Date.new(2026, 11, 16)) # what IssueRelation does for a "follows" relation

    list = stages(issue).to_a
    assert_equal issue.reload.start_date, list.first.planned_start_date
    assert_equal issue.due_date, list.last.planned_end_date
    assert_equal [3, 3, 3], list.map { |s| days(s) }
  end

  # The due date follows a new start date as a change of the issue itself: in its history, before Redmine's callbacks
  def test_the_due_date_that_follows_a_new_start_date_is_in_the_history
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    due_before = issue.due_date
    issue.reload.init_journal(User.find(2))
    issue.update!(start_date: Date.new(2026, 11, 9))

    assert_equal due_before + 7, issue.reload.due_date
    details = issue.journals.reorder(:id).last.details.map(&:prop_key)
    assert_includes details, 'start_date'
    assert_includes details, 'due_date'
  end

  def test_a_new_start_date_on_a_weekend_is_moved_to_the_next_working_day
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    issue.update!(start_date: Date.new(2026, 11, 7)) # Saturday
    assert_equal Date.new(2026, 11, 9), issue.reload.start_date
    assert_equal Date.new(2026, 11, 9), stages(issue).first.planned_start_date
  end

  # On the last stage (the only adjustable one), that stage itself ends on the new due date
  def test_on_the_last_stage_a_new_due_date_moves_its_end
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 3, start_date: Date.new(2026, 11, 2))
    last = stages(issue).last
    issue.update!(due_date: last.planned_end_date + 3)
    assert_equal issue.reload.due_date, stages(issue).last.planned_end_date
  end

  def test_on_the_last_stage_a_due_date_before_it_begins_is_refused
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 3, start_date: Date.new(2026, 11, 2))
    issue.due_date = stages(issue).last.planned_start_date - 1
    assert_not issue.save
    assert issue.errors[:due_date].present?
  end

  def test_a_due_date_on_a_weekend_is_moved_to_the_end_of_the_plan
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2, start_date: Date.new(2026, 11, 2))
    issue.update!(due_date: Date.new(2026, 11, 14)) # Saturday
    assert_equal Date.new(2026, 11, 13), issue.reload.due_date, 'the working day before it'
    assert_equal Date.new(2026, 11, 13), stages(issue).last.planned_end_date
  end

  # A stage that counts every day keeps its days, counted its way, when the start moves
  def test_a_new_start_date_keeps_a_stage_that_counts_every_day
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    stage2 = stages(issue).to_a[1]
    stage2.update!(count_non_working: true, planned_end_date: stage2.planned_start_date + 4) # 5 days in a row
    issue.reload.update!(start_date: Date.new(2026, 11, 9))
    assert_equal 5, days(stages(issue).to_a[1])
  end

  # Created in the second status: the first stage was never entered, so the start date does not move the plan
  def test_the_start_date_does_not_move_the_plan_when_the_first_stage_was_never_entered
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2, start_date: Date.new(2026, 11, 2))
    before = stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }
    issue.update!(start_date: Date.new(2026, 11, 9))
    assert_equal before, stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_a_closed_issue_is_not_replanned
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    issue.update!(status_id: 5)
    before = stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }
    issue.reload.update!(start_date: Date.new(2026, 11, 9))
    assert_equal before, stages(issue).map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_a_due_date_far_away_is_refused
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2, start_date: Date.new(2026, 11, 2))
    issue.due_date = Date.new(9999, 12, 31)
    assert_not issue.save
    assert issue.errors[:base].present?
  end

  # ---- An issue moved to a sequential tracker ------------------------------------------------

  def test_moving_an_issue_to_a_sequential_tracker_lays_out_its_stages_from_the_start_date
    issue = Issue.generate!(project_id: 1, tracker_id: 2, status_id: 1, start_date: Date.new(2026, 11, 2), due_date: Date.new(2026, 11, 3))
    assert_empty issue.issue_stages.reload

    issue.reload.update!(tracker_id: 1)

    list = stages(issue).to_a
    assert_equal 3, list.size
    assert_equal Date.new(2026, 11, 2), list.first.planned_start_date
    assert_equal [3, 3, 3], list.map { |st| days(st) }
    assert_equal 'in_progress', list.first.stage_status, 'the stage of the current status is under way'
    assert_equal list.last.planned_end_date, issue.reload.due_date, 'the due date is the end of the plan'
  end

  def test_moving_without_a_start_date_starts_today_or_the_next_working_day
    issue = Issue.generate!(project_id: 1, tracker_id: 2, status_id: 1, start_date: nil, due_date: nil)
    issue.reload.update!(tracker_id: 1)
    assert_equal RedmineSequentialTasks::WorkingDayCalculator.next_working_day(User.current.today), issue.reload.start_date
    assert_equal 3, stages(issue).size
  end

  def test_moving_between_sequential_trackers_replaces_the_stages
    other = SequentialTaskSetting.create!(tracker_id: 2, enabled: true)
    [1, 2].each_with_index { |st, i| other.steps.create!(status_id: st, position: i + 1, default_duration_days: 5) }
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    issue.reload.update!(tracker_id: 2)
    assert_equal [5, 5], stages(issue).map { |st| days(st) }
  end

  def test_moving_is_refused_when_the_workflow_keeps_the_due_date_read_only
    issue = Issue.generate!(project_id: 1, tracker_id: 2, status_id: 1, start_date: Date.new(2026, 11, 2), due_date: Date.new(2026, 11, 3))
    # user 2 (jsmith) is a Manager (role 1) of project 1; the rule is for the new tracker
    WorkflowPermission.create!(tracker_id: 1, old_status_id: 1, role_id: 1, field_name: 'due_date', rule: 'readonly')
    User.current = User.find(2)
    issue.reload.tracker_id = 1
    assert !issue.save
    assert_includes issue.errors.full_messages.join, ::I18n.t('sequential_tasks.flash.tracker_dates_not_changeable')
    assert_equal 2, issue.reload.tracker_id
    assert_equal Date.new(2026, 11, 3), issue.due_date
    assert_empty issue.issue_stages.reload
  ensure
    User.current = nil
  end

  def test_moving_is_allowed_when_the_read_only_date_does_not_change
    issue = Issue.generate!(project_id: 1, tracker_id: 2, status_id: 1, start_date: Date.new(2026, 11, 2), due_date: Date.new(2026, 11, 12))
    WorkflowPermission.create!(tracker_id: 1, old_status_id: 1, role_id: 1, field_name: 'due_date', rule: 'readonly')
    User.current = User.find(2)
    issue.reload.update!(tracker_id: 1) # 3/3/3 from Monday 11/02 ends on 11/12: the due date stays
    assert_equal 3, stages(issue).size
  ensure
    User.current = nil
  end

  def test_moving_away_from_a_sequential_tracker_keeps_the_stages
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    issue.reload.update!(tracker_id: 2)
    assert_equal 3, stages(issue).size
  end
end
