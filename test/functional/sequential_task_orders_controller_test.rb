# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# placing an issue among its siblings by hand.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook); the anonymous user may not edit issues.
class SequentialTaskOrdersControllerTest < Redmine::ControllerTest
  tests SequentialTaskOrdersController

  def setup
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    setting.steps.create!(status_id: 1, position: 1, default_duration_days: 3)
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all

    @a = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'A')
    @b = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'B')
    @c = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'C')
    @request.session[:user_id] = 2
  end

  def move(issue, before, extra = {})
    put :update, params: { project_id: 'ecookbook', issue_id: issue.id, before_id: before&.id }.merge(extra)
  end

  def top_level_order
    ids = [@a, @b, @c].map(&:id)
    SequentialTaskIssue.where(issue_id: ids, branched_from_issue_id: nil).order(:position, :issue_id).pluck(:issue_id)
  end

  def test_moving_an_issue_numbers_all_its_siblings_and_creates_the_missing_records
    move(@c, @a)
    assert_response :no_content
    assert_equal [@c.id, @a.id, @b.id], top_level_order
    # the project's other issues of this tracker (Redmine fixtures) are siblings too, so the whole list is 1..n
    all = SequentialTaskIssue.where(branched_from_issue_id: nil).order(:position).pluck(:position)
    assert_equal (1..all.size).to_a, all
    assert_operator all.size, :>=, 3
  end

  def test_an_issue_can_be_moved_to_the_end
    move(@a, nil)
    assert_response :no_content
    assert_equal [@b.id, @c.id, @a.id], top_level_order
  end

  def test_other_issues_of_the_project_keep_their_place_in_the_order
    # an issue of another tracker (not enabled) and the three ours: only enabled-tracker issues are siblings
    other = Issue.generate!(project_id: 1, tracker_id: 2, subject: 'other tracker')
    move(@c, @a)
    assert_nil SequentialTaskIssue.find_by(issue_id: other.id)
  end

  def test_branches_are_ordered_among_the_branches_of_the_same_parent
    b1 = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'b1')
    b2 = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'b2')
    SequentialTaskIssue.create!(issue_id: b1.id, branched_from_issue_id: @a.id, position: 1)
    SequentialTaskIssue.create!(issue_id: b2.id, branched_from_issue_id: @a.id, position: 2)

    move(b2, b1)
    assert_response :no_content
    assert_equal 1, SequentialTaskIssue.find_by(issue_id: b2.id).position
    assert_equal 2, SequentialTaskIssue.find_by(issue_id: b1.id).position
    assert_equal @a.id, SequentialTaskIssue.find_by(issue_id: b2.id).branched_from_issue_id, 'the branch stays under its parent'
    assert_equal 0, SequentialTaskIssue.where(issue_id: @a.id).count, 'top-level issues are not touched'
  end

  def test_moving_before_an_issue_that_is_not_a_sibling_is_refused_and_changes_nothing
    b1 = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'b1')
    SequentialTaskIssue.create!(issue_id: b1.id, branched_from_issue_id: @a.id, position: 1)
    before = SequentialTaskIssue.order(:id).pluck(:issue_id, :position, :branched_from_issue_id)

    move(b1, @b)
    assert_response :unprocessable_entity
    assert_equal before, SequentialTaskIssue.order(:id).pluck(:issue_id, :position, :branched_from_issue_id)
  end

  def test_moving_before_an_unknown_issue_is_refused
    move(@a, Issue.new { |i| i.id = 999_999 })
    assert_response :unprocessable_entity
    assert_equal 0, SequentialTaskIssue.count
  end

  def test_users_who_may_not_edit_issues_cannot_reorder
    @request.session[:user_id] = nil
    move(@c, @a)
    assert_not_equal 204, response.status
    assert_equal 0, SequentialTaskIssue.count
  end

  def test_an_issue_the_user_cannot_see_is_not_found
    @c.update_columns(is_private: true)
    @request.session[:user_id] = 3 # a developer who is not the author or assignee of the private issue
    move(@c, @a)
    assert_response :not_found
    assert_equal 0, SequentialTaskIssue.count
  end

  def test_an_issue_of_a_tracker_that_is_not_enabled_is_not_found
    other = Issue.generate!(project_id: 1, tracker_id: 2, subject: 'other tracker')
    move(other, @a)
    assert_response :not_found
  end

  def test_an_issue_of_another_project_is_not_found
    foreign = Issue.generate!(project_id: 3, tracker_id: 1)
    move(foreign, @a)
    assert_response :not_found
  end

  def test_the_order_cannot_be_changed_when_the_project_module_is_off
    EnabledModule.where(project_id: 1, name: 'sequential_tasks').delete_all
    move(@c, @a)
    assert_response :not_found
    assert_equal 0, SequentialTaskIssue.count
  end
end
