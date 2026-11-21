# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Creating a branched task from the screen. Redmine fixtures: user 2 (jsmith) is a Manager of project 1.
class SequentialTaskBranchesControllerTest < Redmine::ControllerTest
  tests SequentialTaskBranchesController

  def setup
    Project.find(1).enable_module!(:sequential_tasks)
    @parent = Issue.generate!(project_id: 1, tracker_id: 1, author: User.find(2), subject: 'Parent')
    @request.session[:user_id] = 2
  end

  def test_a_branch_is_created_with_the_subject_given
    assert_difference 'Issue.count', 1 do
      post :create, params: { issue_id: @parent.id, subject: 'Child' }
    end
    child = Issue.order(:id).last
    assert_equal 'Child', child.subject
    assert_equal @parent.id, SequentialTaskIssue.find_by(issue_id: child.id).branched_from_issue_id
  end

  def test_a_parent_that_does_not_exist_is_not_found
    assert_no_difference 'Issue.count' do
      post :create, params: { issue_id: 999_999, subject: 'Child' }
    end
    assert_response :not_found
  end

  def test_a_private_parent_gives_a_private_child
    @parent.update_columns(is_private: true)
    post :create, params: { issue_id: @parent.id }
    child = Issue.order(:id).last
    assert child.is_private?, 'a subject made from a private parent must not become visible to everyone'
  end

  def test_a_public_parent_gives_a_public_child
    post :create, params: { issue_id: @parent.id }
    assert_not Issue.order(:id).last.is_private?
  end

  def test_nothing_is_created_when_the_module_is_off
    Project.find(1).disable_module!(:sequential_tasks)
    assert_no_difference 'Issue.count' do
      post :create, params: { issue_id: @parent.id, subject: 'Child' }
    end
    assert_response :forbidden
  end

  def test_a_branch_of_a_task_that_starts_later_starts_with_it
    @parent.update_columns(start_date: Date.today + 10)
    post :create, params: { issue_id: @parent.id, subject: 'Child' }
    assert_equal Date.today + 10, Issue.order(:id).last.start_date
  end

  def test_a_branch_of_a_task_that_has_started_starts_today
    @parent.update_columns(start_date: Date.today - 3)
    post :create, params: { issue_id: @parent.id, subject: 'Child' }
    assert_equal Date.today, Issue.order(:id).last.start_date
  end

  def test_a_start_date_given_on_the_form_wins
    @parent.update_columns(start_date: Date.today + 10)
    post :create, params: { issue_id: @parent.id, subject: 'Child', start_date: (Date.today + 2).to_s }
    assert_equal Date.today + 2, Issue.order(:id).last.start_date
  end
end
