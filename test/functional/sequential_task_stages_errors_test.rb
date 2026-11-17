# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The schedule adjustment's refusals and errors: each one leaves the stages as they were and says why.
# Redmine fixtures: user 2 (jsmith) is a Manager (role 1) of project 1; statuses 1 New, 2 Assigned, 3 Resolved.
class SequentialTaskStagesErrorsTest < Redmine::ControllerTest
  tests SequentialTaskStagesController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |st, i| setting.steps.create!(status_id: st, position: i + 1, default_duration_days: 3) }
    @issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, author: User.find(2))
    Project.find(1).enable_module!(:sequential_tasks)
    @request.session[:user_id] = 2
  end

  def t(key)
    ::I18n.t(key, locale: User.find(2).language.presence || 'en')
  end

  def plan(issue = @issue)
    issue.issue_stages.reload.map { |s| [s.planned_start_date, s.planned_end_date] }
  end

  def adjust_second_stage(days)
    second = @issue.issue_stages.reload.find { |s| s.position == 2 }
    put :update, params: { issue_id: @issue.id, stages: { second.id.to_s => { duration_days: days } } }
  end

  def test_an_issue_without_stages_is_not_adjusted
    other = Issue.generate!(project_id: 1, tracker_id: 2, status_id: 1, author: User.find(2))
    put :update, params: { issue_id: other.id, stages: {} }
    assert_redirected_to "/issues/#{other.id}"
    assert_equal t('sequential_tasks.flash.no_stages'), flash[:error]
  end

  def test_a_due_date_the_workflow_keeps_read_only_refuses_the_adjustment
    WorkflowPermission.create!(tracker_id: 1, old_status_id: 1, role_id: 1, field_name: 'due_date', rule: 'readonly')
    before = plan
    adjust_second_stage(6)
    assert_equal t('sequential_tasks.flash.due_not_changeable'), flash[:error]
    assert_equal before, plan
  end

  def test_somebody_else_saving_meanwhile_is_reported_and_nothing_changes
    before = plan
    Issue.any_instance.stubs(:save!).raises(ActiveRecord::StaleObjectError.new)
    adjust_second_stage(6)
    assert_equal t(:notice_issue_update_conflict), flash[:error]
    assert_equal before, plan
  end

  def test_a_save_refused_by_validation_shows_the_reason_and_nothing_changes
    before = plan
    invalid = Issue.new
    invalid.errors.add(:base, 'refused for the test')
    Issue.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(invalid))
    adjust_second_stage(6)
    assert_includes flash[:error], 'refused for the test'
    assert_equal before, plan
  end

  def test_an_issue_that_does_not_exist_is_not_found
    put :update, params: { issue_id: 999_999, stages: {} }
    assert_response :not_found
  end
end
