# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# How far are the branches of an issue? Redmine fixtures: user 2 (jsmith) is a Manager of
# project 1 (ecookbook); status 5 is a closed one.
class SequentialTasksBranchProgressTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all
    @parent = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'the request')
    @kids = 3.times.map do |i|
      kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: "action #{i}")
      SequentialTaskIssue.create!(issue_id: kid.id, branched_from_issue_id: @parent.id, position: i + 1)
      kid
    end
    @request.session[:user_id] = 2
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  def pill(issue)
    css_select("tr[data-id='#{issue.id}'] span.sq-bc").first
  end

  def test_the_parent_shows_how_many_of_its_branches_are_done
    @kids[0].update!(status_id: 5)
    index
    assert_equal '1/3', pill(@parent).text.strip
    assert_includes pill(@parent)['title'], '3'
    assert_includes pill(@parent)['title'], '1'
  end

  def test_finished_branches_count_even_when_the_screen_hides_them
    @kids[0].update!(status_id: 5)
    index # finished issues are hidden by default
    assert_select "tr[data-id='#{@kids[0].id}']", 0
    assert_equal '1/3', pill(@parent).text.strip
  end

  def test_the_mark_is_green_when_every_branch_is_done
    @kids.each { |k| k.update!(status_id: 5) }
    index
    assert_select "tr[data-id='#{@parent.id}'] span.sq-bc.sq-bc-done"
    assert_equal '3/3', pill(@parent).text.strip
  end

  def test_the_mark_is_orange_when_the_parent_is_done_but_branches_are_open
    @parent.update!(status_id: 5)
    @kids[0].update!(status_id: 5)
    index(show_closed: '1')
    assert_select "tr[data-id='#{@parent.id}'] span.sq-bc.sq-bc-warn"
    assert_includes pill(@parent)['title'], '2'
  end

  def test_branches_the_user_may_not_see_are_not_counted
    @kids[1].update_columns(is_private: true)
    @request.session[:user_id] = 3
    index
    assert_equal '0/2', pill(@parent).text.strip
  end

  def test_issues_without_branches_have_no_mark
    index
    assert_select "tr[data-id='#{@kids[0].id}'] span.sq-bc", 0
  end

  def test_the_matrix_has_the_mark_too
    @kids[0].update!(status_id: 5)
    index(view: 'matrix')
    assert_equal '1/3', pill(@parent).text.strip
  end

  def test_the_rows_stay_small
    index
    assert css_select('tr.issue-row').map { |r| r.to_s.bytesize }.max < 3500
  end
end
