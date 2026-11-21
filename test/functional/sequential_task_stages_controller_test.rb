# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Schedule adjustment from the issue screen.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1; statuses 1 New, 2 Assigned, 3 Resolved, 5 Closed.
class SequentialTaskStagesControllerTest < Redmine::ControllerTest
  tests SequentialTaskStagesController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index do |status_id, i|
      setting.steps.create!(status_id: status_id, position: i + 1, default_duration_days: 3)
    end
    @issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, author: User.find(2))
    Project.find(1).enable_module!(:sequential_tasks)
    @request.session[:user_id] = 2
  end

  def stage(position)
    @issue.issue_stages.reload.find { |s| s.position == position }
  end

  def move_to(status_id)
    @issue.reload
    @issue.status_id = status_id
    @issue.save!
  end

  def adjust(durations, mode = nil)
    params = durations.transform_keys { |pos| stage(pos).id.to_s }.transform_values { |d| { duration_days: d } }
    put :update, params: { issue_id: @issue.id, stages: params, mode: mode }.compact
  end

  # an issue in a status that is not one of the stages (here Feedback, 4), before any stage has started
  def outside_issue
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 4, author: User.find(2))
    assert issue.issue_stages.all? { |s| s.stage_status == 'pending' }, 'nothing has started'
    @issue = issue
  end

  def test_a_status_without_a_stage_can_be_adjusted_from_the_first_stage
    outside_issue
    adjust(1 => 5)
    assert_redirected_to "/issues/#{@issue.id}"
    assert_equal 5, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(stage(1).planned_start_date, stage(1).planned_end_date)
  end

  def test_a_status_without_a_stage_can_have_its_start_moved
    outside_issue
    new_start = RedmineSequentialTasks::WorkingDayCalculator.next_working_day(stage(1).planned_start_date + 7)
    put :update, params: { issue_id: @issue.id, stages: {}, start_date: new_start.to_s }
    assert_equal new_start, @issue.reload.start_date
    assert_equal new_start, stage(1).planned_start_date
  end

  def test_a_save_from_the_floating_window_goes_back_to_it
    put :update, params: { issue_id: @issue.id, stages: { stage(1).id.to_s => { duration_days: 4 } }, sq_float: '1' }
    assert_redirected_to "/issues/#{@issue.id}?sq_float=1"
  end

  def test_completed_stages_keep_their_planned_dates
    move_to(2) # stage 1 completed, stage 2 current
    before = stage(1).attributes.slice('planned_start_date', 'planned_end_date')

    adjust(1 => 20, 2 => 5)

    assert_redirected_to "/issues/#{@issue.id}"
    assert_equal before, stage(1).attributes.slice('planned_start_date', 'planned_end_date')
  end

  def test_the_current_stage_keeps_its_start_and_the_later_stages_slide
    move_to(2)
    start2 = stage(2).planned_start_date
    calc = RedmineSequentialTasks::WorkingDayCalculator

    adjust(2 => 6)

    expected_end2 = calc.calculate_end_date(start2, 6)
    assert_equal start2, stage(2).planned_start_date
    assert_equal expected_end2, stage(2).planned_end_date
    assert_equal calc.next_stage_start_date(expected_end2), stage(3).planned_start_date
    assert_equal stage(3).planned_end_date, @issue.reload.due_date
  end

  def test_the_change_is_recorded_in_the_issue_history
    move_to(2)
    assert_difference -> { @issue.journals.count }, 1 do
      adjust(2 => 6)
    end
    assert_includes @issue.journals.reorder(:id).last.notes, I18n.t('sequential_tasks.journal.title', locale: User.find(2).language.presence || 'en')
  end

  def test_a_closed_issue_cannot_be_adjusted
    move_to(5)
    before = @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }

    adjust(3 => 9)

    assert_redirected_to "/issues/#{@issue.id}"
    assert_equal before, @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
    assert flash[:error].present?
  end

  def test_anonymous_users_are_sent_to_login_and_nothing_changes
    @request.session[:user_id] = nil
    before = @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }

    adjust(1 => 9)

    assert_response :redirect
    assert_equal before, @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_nothing_is_adjusted_when_the_module_is_off
    Project.find(1).disable_module!(:sequential_tasks)
    move_to(2)
    adjust(2 => 5)
    assert_response :forbidden
  end

  # mode "fixed_due" keeps the due date where it is, shrinking or growing the other stages instead
  def test_fixed_due_mode_keeps_the_due_date_and_shrinks_the_later_stage
    move_to(2) # stage 2 (3 days) current, stage 3 (3 days) pending; due date is stage 3's planned end
    due_before = @issue.due_date

    adjust({ 2 => 5 }, 'fixed_due') # +2 days on stage 2

    assert_equal due_before, @issue.reload.due_date, 'the due date does not move'
    assert_equal 1, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(stage(3).planned_start_date, stage(3).planned_end_date), 'stage 3 gave the two days back'
  end

  def test_fixed_due_mode_refuses_when_it_does_not_fit_and_changes_nothing
    move_to(2)
    before = @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
    due_before = @issue.due_date

    adjust({ 2 => 20 }, 'fixed_due') # far more than stage 3 could ever give back

    assert_redirected_to "/issues/#{@issue.id}"
    assert flash[:error].present?
    assert_equal due_before, @issue.reload.due_date
    assert_equal before, @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_the_default_mode_is_still_push_the_rest
    move_to(2)
    adjust(2 => 6) # no mode given
    assert_equal stage(3).planned_end_date, @issue.reload.due_date, 'the due date follows, as before'
  end

  # the start date from the adjustment screen
  def adjust_start(new_start, mode = nil, durations = {})
    params = durations.transform_keys { |pos| stage(pos).id.to_s }.transform_values { |d| { duration_days: d } }
    put :update, params: { issue_id: @issue.id, stages: params, start_date: new_start.to_s, mode: mode }.compact
  end

  def days_of(position)
    RedmineSequentialTasks::WorkingDayCalculator.working_days_between(stage(position).planned_start_date, stage(position).planned_end_date)
  end

  def test_moving_the_start_in_push_mode_shifts_every_stage_and_the_due_date
    calc = RedmineSequentialTasks::WorkingDayCalculator
    new_start = calc.next_working_day(stage(1).planned_start_date + 3)

    assert_difference -> { @issue.journals.count }, 1 do
      adjust_start(new_start)
    end

    assert_equal new_start, @issue.reload.start_date
    assert_equal new_start, stage(1).planned_start_date
    assert_equal [3, 3, 3], [days_of(1), days_of(2), days_of(3)], 'each stage keeps its days'
    assert_equal stage(3).planned_end_date, @issue.due_date
    assert_includes @issue.journals.reorder(:id).last.notes, RedmineSequentialTasks::DateFormat.full(new_start) # in the language of the request
  end

  def test_moving_the_start_in_fixed_due_mode_keeps_the_due_date_and_shrinks_the_last_stage
    calc = RedmineSequentialTasks::WorkingDayCalculator
    due_before = @issue.due_date
    new_start = calc.next_working_day(stage(1).planned_start_date + 1) # one working day later

    adjust_start(new_start, 'fixed_due')

    assert_equal new_start, @issue.reload.start_date
    assert_equal due_before, @issue.due_date, 'the due date does not move'
    assert_equal [3, 3, 2], [days_of(1), days_of(2), days_of(3)], 'the last stage gave the day'
  end

  def test_the_start_cannot_be_moved_once_a_stage_has_finished
    move_to(2) # stage 1 finished
    calc = RedmineSequentialTasks::WorkingDayCalculator
    before = @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
    start_before = @issue.reload.start_date

    adjust_start(calc.next_working_day(stage(1).planned_start_date + 3))

    assert_redirected_to "/issues/#{@issue.id}"
    assert flash[:error].present?
    assert_equal start_before, @issue.reload.start_date
    assert_equal before, @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_sending_the_same_start_changes_nothing_about_it
    start = stage(1).planned_start_date
    adjust_start(start, nil, 2 => 4)
    assert_nil flash[:error]
    assert_equal start, stage(1).planned_start_date
    assert_equal 4, days_of(2)
  end

  # the screen trades days across one boundary in "fixed_due" mode and sends both stages of the pair;
  # the stage after them (here the last one, the slack) keeps its days, and so does the due date
  def test_fixed_due_mode_with_a_pair_traded_leaves_the_later_stage_alone
    due_before = @issue.due_date
    adjust({ 1 => 4, 2 => 2 }, 'fixed_due') # 3 + 3 split anew as 4 + 2

    assert_nil flash[:error]
    assert_equal [4, 2, 3], [days_of(1), days_of(2), days_of(3)]
    assert_equal due_before, @issue.reload.due_date
  end

  # the project timeline's adjust mode saves with a fetch and reads a JSON answer
  def test_a_fetch_from_the_timeline_gets_json_and_the_change_is_saved
    put :update, params: { issue_id: @issue.id, stages: { stage(1).id.to_s => { duration_days: 5 } }, mode: 'push' }, xhr: true

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal true, json['ok']
    assert_equal 5, days_of(1)
    assert json['notice'].present?, 'the message comes in the answer'
  end

  def test_a_refused_fetch_gets_json_with_the_reason
    move_to(2)
    put :update, params: { issue_id: @issue.id, stages: {}, start_date: (stage(1).planned_start_date + 7).to_s }, xhr: true

    assert_response :success
    json = ActiveSupport::JSON.decode(response.body)
    assert_equal false, json['ok']
    assert json['error'].present?
  end

  # a stage that counts the non-working days too, switched per issue on "adjust the schedule"
  def test_a_stage_can_count_the_non_working_days_too
    calc = RedmineSequentialTasks::WorkingDayCalculator
    start2 = stage(2).planned_start_date
    assert_difference -> { @issue.journals.count }, 1 do
      put :update, params: { issue_id: @issue.id, mode: 'push',
                             stages: { stage(2).id.to_s => { duration_days: 7, count_non_working: '1' } } }
    end

    assert stage(2).count_non_working
    assert_equal start2 + 6, stage(2).planned_end_date, 'seven days in a row, the weekend included'
    assert_equal calc.next_stage_start_date(start2 + 6), stage(3).planned_start_date
    assert_equal 7, RedmineSequentialTasks::StageRescheduler.new(@issue.issue_stages.reload.to_a, stage(1)).current_duration(stage(2))
    assert_includes @issue.journals.reorder(:id).last.notes, I18n.t('sequential_tasks.journal.count_all', locale: User.find(2).language.presence || 'en')
  end

  def test_switching_back_counts_working_days_again
    stage(2).update!(count_non_working: true)
    put :update, params: { issue_id: @issue.id, mode: 'push',
                           stages: { stage(2).id.to_s => { duration_days: 3, count_non_working: '0' } } }

    refute stage(2).count_non_working
    assert_equal 3, RedmineSequentialTasks::WorkingDayCalculator.working_days_between(stage(2).planned_start_date, stage(2).planned_end_date)
  end

  def test_fixed_due_mode_keeps_the_due_date_when_a_stage_counts_every_day
    due_before = @issue.due_date
    put :update, params: { issue_id: @issue.id, mode: 'fixed_due',
                           stages: { stage(1).id.to_s => { duration_days: 3, count_non_working: '1' } } }

    assert_nil flash[:error]
    assert_equal due_before, @issue.reload.due_date, 'the slack takes up the difference, measured in dates'
  end

  # no working day within half a year
  def test_the_schedule_is_not_adjusted_without_any_working_day
    before = @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    adjust(2 => 6)

    assert_redirected_to "/issues/#{@issue.id}"
    assert_equal I18n.t('sequential_tasks.flash.no_working_day', locale: User.find(2).language.presence || 'en'), flash[:error]
    assert_equal before, @issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_an_issue_of_a_sequential_tracker_is_not_created_without_any_working_day
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    issue = Issue.new(project_id: 1, tracker_id: 1, status_id: 1, author_id: 2, subject: 'no working day', priority: IssuePriority.first)
    assert_no_difference -> { Issue.count } do
      assert_not issue.save
    end
    assert issue.errors.full_messages.any? { |m| m.include?(I18n.t('sequential_tasks.flash.no_working_day', locale: I18n.locale).first(10)) }
  end

  def test_the_due_date_is_not_changed_directly_without_any_working_day
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    issue = @issue.reload
    issue.due_date = issue.due_date + 3
    assert_not issue.save
    assert issue.errors[:base].any?
  end

  def test_other_trackers_are_not_affected
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    issue = Issue.new(project_id: 1, tracker_id: 2, status_id: 1, author_id: 2, subject: 'not sequential', priority: IssuePriority.first)
    assert issue.save, issue.errors.full_messages.join(', ')
  end

  # Limits on the server (review 2026-11-14)
  def test_a_huge_number_of_days_is_capped_at_365
    adjust({ 2 => 1_000_000_000 }, 'push')
    assert_nil flash[:error]
    assert_equal 365, days_of(2)
  end

  def test_unreadable_days_keep_the_current_ones
    put :update, params: { issue_id: @issue.id, mode: 'push', stages: { stage(2).id.to_s => { duration_days: 'abc' } } }
    assert_equal 3, days_of(2)
  end

  def test_a_malformed_stages_parameter_is_ignored_not_an_error
    put :update, params: { issue_id: @issue.id, mode: 'push', stages: 'abc' }
    assert_redirected_to "/issues/#{@issue.id}"
    put :update, params: { issue_id: @issue.id, mode: 'push', stages: { stage(2).id.to_s => { duration_days: ['1'] } } }
    assert_redirected_to "/issues/#{@issue.id}"
    assert_equal 3, days_of(2)
  end

  def test_a_start_date_far_away_is_refused
    adjust_start(Date.today.next_year(50))
    assert flash[:error].present?
    refute_equal Date.today.next_year(50), @issue.reload.start_date
  end

  # 2026-11-15: due date first, a later start is taken up by the first stage (the screen sends its new days)
  def test_due_date_first_with_a_later_start_shortens_the_first_stage_only
    calc = RedmineSequentialTasks::WorkingDayCalculator
    due_before = @issue.due_date
    first_end = stage(1).planned_end_date
    new_start = calc.next_working_day(stage(1).planned_start_date + 1)

    adjust_start(new_start, 'fixed_due', 1 => 2, 2 => 3)

    assert_nil flash[:error]
    assert_equal [2, 3, 3], [days_of(1), days_of(2), days_of(3)]
    assert_equal first_end, stage(1).planned_end_date, 'the end of the first stage stays'
    assert_equal due_before, @issue.reload.due_date
  end
end
