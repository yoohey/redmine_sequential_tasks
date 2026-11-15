# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# moving an issue to another version (the groups of the timeline).
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTaskVersionsControllerTest < Redmine::ControllerTest
  tests SequentialTaskVersionsController

  def setup
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    setting.steps.create!(status_id: 1, position: 1, default_duration_days: 3)
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    @v1 = Version.create!(project_id: 1, name: 'R1', effective_date: Date.today + 10)
    @v2 = Version.create!(project_id: 1, name: 'R2', effective_date: Date.today + 24)
    @issue = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'feature', fixed_version_id: @v1.id)
    @request.session[:user_id] = 2
  end

  def assign(issue, version, extra = {})
    put :update, params: { project_id: 'ecookbook', issue_id: issue.id, version_id: version&.id }.merge(extra)
  end

  def test_the_issue_gets_the_other_version
    assign(@issue, @v2)
    assert_response :no_content
    assert_equal @v2.id, @issue.reload.fixed_version_id
  end

  def test_an_empty_version_takes_the_version_off
    assign(@issue, nil)
    assert_response :no_content
    assert_nil @issue.reload.fixed_version_id
  end

  def test_the_change_is_in_the_history_of_the_issue
    assert_difference 'Journal.count', 1 do
      assign(@issue, @v2)
    end
    detail = Journal.order(:id).last.details.find { |d| d.prop_key == 'fixed_version_id' }
    assert_equal [@v1.id.to_s, @v2.id.to_s], [detail.old_value, detail.value]
    assert_equal 2, Journal.order(:id).last.user_id
  end

  def test_a_closed_version_cannot_be_assigned_and_nothing_changes
    @v2.update!(status: 'closed')
    assign(@issue, @v2)
    assert_response :unprocessable_entity
    assert_equal @v1.id, @issue.reload.fixed_version_id
    assert response.body.present?, 'the reason is in the response'
  end

  def test_a_version_of_another_project_that_is_not_shared_is_refused
    other = Version.create!(project_id: 3, name: 'elsewhere', sharing: 'none')
    assign(@issue, other)
    assert_response :unprocessable_entity
    assert_equal @v1.id, @issue.reload.fixed_version_id
  end

  def test_users_who_may_not_edit_issues_cannot_change_the_version
    @request.session[:user_id] = nil
    assign(@issue, @v2)
    assert_not_equal 204, response.status
    assert_equal @v1.id, @issue.reload.fixed_version_id
  end

  def test_an_issue_the_user_cannot_see_is_not_found
    @issue.update_columns(is_private: true)
    @request.session[:user_id] = 3
    assign(@issue, @v2)
    assert_response :not_found
  end

  def test_an_issue_of_another_project_is_not_found
    foreign = Issue.generate!(project_id: 3, tracker_id: 1)
    assign(foreign, @v2)
    assert_response :not_found
  end

  def test_the_change_is_refused_when_the_project_module_is_off
    EnabledModule.where(project_id: 1, name: 'sequential_tasks').delete_all
    assign(@issue, @v2)
    assert_response :not_found
    assert_equal @v1.id, @issue.reload.fixed_version_id
  end

  def test_the_workflow_may_forbid_changing_the_version
    WorkflowPermission.create!(tracker_id: 1, old_status_id: @issue.status_id, role_id: 1, field_name: 'fixed_version_id', rule: 'readonly')
    assign(@issue, @v2)
    assert_response :unprocessable_entity
    assert_equal @v1.id, @issue.reload.fixed_version_id
  end
end
