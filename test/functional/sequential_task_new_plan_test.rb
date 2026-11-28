# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Planning the stages on the new issue form: the stage timeline in the form, the days sent with the issue, and the
# due date given by hand. Redmine fixtures: user 2 (jsmith) is a Manager of project 1; tracker 1's default status is 1.
class SequentialTaskNewPlanTest < Redmine::ControllerTest
  tests IssuesController

  MONDAY = Date.new(2026, 11, 30)

  def setup
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [[1, 2], [2, 3]].each_with_index { |(s, d), i| @setting.steps.create!(status_id: s, position: i + 1, default_duration_days: d) }
    Project.find(1).enable_module!(:sequential_tasks)
    @request.session[:user_id] = 2
  end

  def issue_params(attrs = {})
    { tracker_id: 1, subject: 'planned while creating', start_date: MONDAY.to_s, due_date: '' }.merge(attrs)
  end

  def sq_plan(days, all = {})
    { tracker_id: '1', steps: days.to_h { |status_id, n| [status_id.to_s, { days: n.to_s, all: all[status_id] ? '1' : '0' }] } }
  end

  def spans(issue)
    issue.issue_stages.order(:position).map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def test_the_new_issue_form_shows_the_stage_timeline_open_for_changing
    get :new, params: { project_id: 1, issue: { tracker_id: 1 } }
    assert_response :success
    assert_select '#issue-form #sq-stage-timeline.sq-new-plan' do
      assert_select 'input[type=hidden][name="sq_plan[tracker_id]"][value="1"]'
      assert_select '.stage-drag-seg', 2
      assert_select 'input.stage-duration-input[name="sq_plan[steps][1][days]"][value="2"]'
      assert_select 'input.stage-duration-input[name="sq_plan[steps][2][days]"][value="3"]'
      assert_select '.stage-drag-handle[title]', 0
    end
  end

  def test_not_for_a_tracker_without_stages_nor_without_the_module
    get :new, params: { project_id: 1, issue: { tracker_id: 2 } }
    assert_select '#sq-stage-timeline', 0
    Project.find(1).disable_module!(:sequential_tasks)
    get :new, params: { project_id: 1, issue: { tracker_id: 1 } }
    assert_select '#sq-stage-timeline', 0
  end

  def test_not_on_the_edit_form_of_an_issue
    issue = Issue.generate!(project_id: 1, tracker_id: 1)
    get :edit, params: { id: issue.id }
    assert_response :success
    assert_select '.sq-new-plan', 0
  end

  def test_a_rebuilt_form_keeps_the_days_for_the_same_tracker_only
    post :new, params: { project_id: 1, issue: issue_params, sq_plan: sq_plan(1 => 4, 2 => 1) }, xhr: true, format: :js
    assert_response :success
    assert_include 'name=\\"sq_plan[steps][1][days]\\" class=\\"stage-duration-input\\" value=\\"4\\"', response.body
    assert_include 'data-fill-due=\\"0\\"', response.body

    post :new, params: { project_id: 1, issue: issue_params, sq_plan: sq_plan(1 => 4).merge(tracker_id: '3') }, xhr: true, format: :js
    assert_include 'name=\\"sq_plan[steps][1][days]\\" class=\\"stage-duration-input\\" value=\\"2\\"', response.body, 'made for another tracker: the standard days'
    assert_include 'data-fill-due=\\"1\\"', response.body
  end

  def test_creating_with_the_days_chosen_on_the_form
    assert_difference 'Issue.count' do
      post :create, params: { project_id: 1, issue: issue_params, sq_plan: sq_plan({ 1 => 4, 2 => 2 }, 2 => true) }
    end
    issue = Issue.order(:id).last
    assert_equal [[MONDAY, MONDAY + 3], [MONDAY + 4, MONDAY + 5]], spans(issue), 'Thursday; then Friday and Saturday (every day counted)'
    assert issue.issue_stages.order(:position).last.count_non_working
    assert_equal MONDAY + 5, issue.due_date
  end

  def test_a_due_date_given_by_hand_makes_the_last_stage_end_on_it
    post :create, params: { project_id: 1, issue: issue_params(due_date: (MONDAY + 9).to_s), sq_plan: sq_plan(1 => 2, 2 => 3) }
    issue = Issue.order(:id).last
    assert_equal [[MONDAY, MONDAY + 1], [MONDAY + 2, MONDAY + 9]], spans(issue)
    assert_equal MONDAY + 9, issue.due_date
  end

  def test_a_due_date_the_stages_do_not_fit_in_is_refused
    assert_no_difference 'Issue.count' do
      post :create, params: { project_id: 1, issue: issue_params(due_date: MONDAY.to_s), sq_plan: sq_plan(1 => 2, 2 => 3) }
    end
    assert_response :success
    assert_select '#errorExplanation', /#{Regexp.escape(I18n.t('sequential_tasks.flash.cannot_fit_new_due_date', locale: :en)[0, 20])}/
  end

  def test_without_a_plan_from_the_form_the_standard_days_as_before
    post :create, params: { project_id: 1, issue: issue_params(due_date: (MONDAY + 20).to_s) }
    issue = Issue.order(:id).last
    assert_equal [[MONDAY, MONDAY + 1], [MONDAY + 2, MONDAY + 4]], spans(issue)
    assert_equal MONDAY + 20, issue.due_date, 'a due date given without the plan is kept as it is'
  end
end
