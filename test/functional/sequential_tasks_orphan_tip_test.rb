# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# A branch whose parent is not in the table gets a small "branched from #id" link. Its tip names the parent only when
# the user may see it. Redmine fixtures: user 3 (dlopper) is a Developer (role 2) of project 1, and a Developer sees
# only the private issues they wrote or are assigned to.
class SequentialTasksOrphanTipTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2].each_with_index { |st, i| setting.steps.create!(status_id: st, position: i + 1, default_duration_days: 3) }
    Project.find(1).enable_module!(:sequential_tasks)
    Role.find(2).update!(issues_visibility: 'default')
    @parent = Issue.generate!(project_id: 1, tracker_id: 2, author: User.find(2), subject: 'Secret parent', is_private: true)
    @child = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, author: User.find(2), subject: 'Visible branch')
    SequentialTaskIssue.create!(issue_id: @child.id, branched_from_issue_id: @parent.id, position: 1)
  end

  def tip
    css_select("a.sq-orphan[href$='/issues/#{@parent.id}']").first&.[]('title')
  end

  def test_a_parent_the_user_cannot_see_is_named_by_its_number_only
    @request.session[:user_id] = 3
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    assert tip, 'the branch shows its parent link'
    assert_not_includes tip, 'Secret parent'
    assert_includes tip, "##{@parent.id}"
  end

  def test_a_parent_the_user_can_see_is_named_with_its_subject
    @request.session[:user_id] = 2
    get :index, params: { project_id: 'ecookbook' }
    assert_includes tip.to_s, 'Secret parent'
  end
end
