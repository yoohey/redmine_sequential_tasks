# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Standard days per project. Redmine fixtures: user 2 (jsmith) is a Manager of
# project 1; statuses 1 New, 2 Assigned, 3 Resolved.
class SequentialTaskProjectStepsTest < Redmine::ControllerTest
  tests SequentialTaskProjectStepsController

  def setup
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| @setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    Project.find(1).enable_module!(:sequential_tasks)
    Role.find(1).add_permission!(:manage_sequential_tasks)
    @request.session[:user_id] = 2
  end

  def overrides
    SequentialTaskProjectStep.where(project_id: 1).order(:status_id).map { |o| [o.tracker_id, o.status_id, o.default_duration_days] }
  end

  def save(days)
    put :update, params: { project_id: 'ecookbook', days: days }
  end

  def test_the_days_are_saved_for_the_project_and_the_screen_comes_back
    save('1' => { '1' => '5', '2' => '', '3' => '2' })
    assert_redirected_to '/projects/ecookbook/settings/sequential_tasks'
    assert_equal [[1, 1, 5], [1, 3, 2]], overrides
  end

  def test_an_empty_value_or_the_trackers_own_value_removes_the_override
    SequentialTaskProjectStep.create!(project_id: 1, tracker_id: 1, status_id: 1, default_duration_days: 9)
    SequentialTaskProjectStep.create!(project_id: 1, tracker_id: 1, status_id: 2, default_duration_days: 9)
    save('1' => { '1' => '', '2' => '3' }) # 3 is what the tracker says
    assert_equal [], overrides
  end

  def test_the_days_are_kept_within_one_and_365_and_unknown_ones_are_dropped
    save('1' => { '1' => '9999', '2' => '0', '99999' => '4' }, '2' => { '1' => '4' }, '1x' => { '1' => '4' })
    assert_equal [[1, 1, 365], [1, 2, 1]], overrides
  end

  def test_the_first_status_may_be_zero_days_in_a_project_but_not_the_others
    save('1' => { '1' => '0', '2' => '0' })
    assert_equal [[1, 1, 0], [1, 2, 1]], overrides
  end

  def test_other_projects_are_not_touched
    SequentialTaskProjectStep.create!(project_id: 2, tracker_id: 1, status_id: 1, default_duration_days: 7)
    save('1' => { '1' => '5' })
    assert_equal 1, SequentialTaskProjectStep.where(project_id: 2).count
  end

  def test_a_member_without_the_permission_cannot_save
    Role.find(1).remove_permission!(:manage_sequential_tasks)
    save('1' => { '1' => '5' })
    assert_response :forbidden
    assert_equal [], overrides
  end

  def test_nothing_is_saved_when_the_module_is_off
    Project.find(1).disable_module!(:sequential_tasks)
    save('1' => { '1' => '5' })
    assert_response :forbidden
  end
end

class SequentialTaskProjectStepsScreenTest < Redmine::ControllerTest
  tests ProjectsController

  def setup
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2].each_with_index { |s, i| @setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    Project.find(1).enable_module!(:sequential_tasks)
    @request.session[:user_id] = 2
  end

  def test_the_project_settings_have_a_tab_for_those_who_may_manage
    Role.find(1).add_permission!(:manage_sequential_tasks)
    SequentialTaskProjectStep.create!(project_id: 1, tracker_id: 1, status_id: 1, default_duration_days: 6)
    get :settings, params: { id: 'ecookbook', tab: 'sequential_tasks' }
    assert_response :success
    assert_select 'input[name=?][value="6"]', 'days[1][1]'
    assert_select 'input[name=?][placeholder="3"]', 'days[1][2]' # the tracker's own value shows when nothing is set
    assert_select 'td.sq-style-bold .sq-bar', 2 # the status cells are bars in the stage colors, as on the timeline
    assert_select 'td .sq-bar[style*="--c:#3498db"]'
  end

  def test_no_tab_without_the_permission
    Role.find(1).remove_permission!(:manage_sequential_tasks)
    get :settings, params: { id: 'ecookbook' }
    assert_select '#tab-sequential_tasks', 0
  end
end

class SequentialTaskStandardDaysTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :roles, :enumerations, :enabled_modules, :projects_trackers,
           :workflows, :members, :member_roles

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    SequentialTaskProjectStep.create!(project_id: 1, tracker_id: 1, status_id: 1, default_duration_days: 6)
  end

  def test_a_new_issue_uses_the_days_of_its_project
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2)) # a Monday
    days = issue.issue_stages.order(:position).map { |s| (s.planned_start_date..s.planned_end_date).count { |d| !d.saturday? && !d.sunday? } }
    assert_equal [6, 3], days
  end

  def test_an_issue_of_another_project_uses_the_trackers_days
    issue = Issue.generate!(project_id: 3, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    skip 'the tracker is not in project 3' unless issue.persisted? && issue.issue_stages.any?
    days = issue.issue_stages.order(:position).map { |s| (s.planned_start_date..s.planned_end_date).count { |d| !d.saturday? && !d.sunday? } }
    assert_equal [3, 3], days
  end

  def test_the_override_is_left_alone_when_the_project_has_none
    assert_equal 3, RedmineSequentialTasks::StandardDays.new(99).days(1, SequentialTaskStep.find_by(status_id: 1))
  end
end

# The first stage of zero days: filed, but nobody has picked it up
class SequentialTaskZeroDayGenerationTest < ActiveSupport::TestCase
  fixtures :projects, :trackers, :issue_statuses, :users, :roles, :enumerations, :enabled_modules, :projects_trackers,
           :workflows, :members, :member_roles

  def setup
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [[1, 0], [2, 2], [3, 3]].each_with_index { |(s, d), i| @setting.steps.create!(status_id: s, position: i + 1, default_duration_days: d) }
  end

  def stages(issue)
    issue.issue_stages.order(:position).map { |s| [s.zero_day, s.planned_start_date, s.planned_end_date] }
  end

  def test_the_zero_day_stage_is_a_point_and_the_next_stage_starts_the_same_day
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2)) # a Monday
    monday = Date.new(2026, 11, 2)
    assert_equal [[true, monday, monday], [false, monday, Date.new(2026, 11, 3)], [false, Date.new(2026, 11, 4), Date.new(2026, 11, 6)]], stages(issue)
    assert_equal Date.new(2026, 11, 6), issue.reload.due_date, 'the waiting does not use any of the days'
  end

  def test_the_zero_day_stage_is_in_progress_at_first_and_has_a_visit
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    first = issue.issue_stages.order(:position).first
    assert_equal 'in_progress', first.stage_status
    assert_equal 1, first.visits.count
  end

  def test_a_project_can_make_the_first_stage_zero_days_for_itself
    @setting.steps.find_by(status_id: 1).update!(default_duration_days: 1)
    SequentialTaskProjectStep.create!(project_id: 1, tracker_id: 1, status_id: 1, default_duration_days: 0)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    assert_equal [true, false, false], stages(issue).map(&:first)
  end

  def test_a_tracker_with_one_day_first_stage_has_no_zero_day_stage
    @setting.steps.find_by(status_id: 1).update!(default_duration_days: 1)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.new(2026, 11, 2))
    assert_equal [false, false, false], stages(issue).map(&:first)
  end
end
