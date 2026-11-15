# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The view with an issue at the top: the project screen narrowed to one issue and the
# branches under it, shown inside the issue page. Redmine fixtures: user 2 (jsmith) is a Manager of project 1.
class SequentialTasksRootViewTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all
    @top = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Top')
    @kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Kid')
    @grandkid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Grandkid')
    @other = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Other')
    SequentialTaskIssue.create!(issue_id: @kid.id, branched_from_issue_id: @top.id, position: 1)
    SequentialTaskIssue.create!(issue_id: @grandkid.id, branched_from_issue_id: @kid.id, position: 1)
    @request.session[:user_id] = 2
  end

  def shown_ids
    css_select('tr.issue-row a.sq-subj').map { |a| a['href'][%r{/issues/(\d+)}, 1].to_i }
  end

  def test_the_root_param_narrows_the_screen_to_the_issue_and_its_branches
    get :index, params: { project_id: 'ecookbook', root: @top.id }
    assert_response :success
    assert_equal [@top.id, @kid.id, @grandkid.id], shown_ids
  end

  def test_the_view_is_the_inline_one_without_the_toolbar_or_the_handles
    get :index, params: { project_id: 'ecookbook', root: @top.id }
    assert_select '#sq-root.sq-inline'
    assert_select '.sq-tb', 0
    assert_select '.sq-plus', 0
    assert_select '.sq-hd', 0
    assert_select '.sq-rz' # the width of the issue column can still be changed
  end

  def test_finished_issues_are_shown_in_the_inline_view
    @kid.init_journal(User.find(2))
    @kid.status = IssueStatus.find(5)
    @kid.save!
    get :index, params: { project_id: 'ecookbook', root: @top.id }
    assert_includes shown_ids, @kid.id
  end

  def test_links_of_the_inline_view_open_in_the_page_that_holds_the_frame
    get :index, params: { project_id: 'ecookbook', root: @top.id, sq_embed: '1' }
    assert_select 'base[target=_parent]'
  end

  def test_an_unknown_root_shows_the_ordinary_screen
    get :index, params: { project_id: 'ecookbook', root: 'abc' }
    assert_response :success
    assert_select '#sq-root.sq-inline', 0
    assert_includes shown_ids, @other.id
  end

  def test_an_issue_without_branches_shows_only_itself
    get :index, params: { project_id: 'ecookbook', root: @other.id }
    assert_equal [@other.id], shown_ids
  end
end

class SequentialTasksRootViewInIssueTest < Redmine::ControllerTest
  tests IssuesController

  def setup
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all
    @top = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Top')
    @kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Kid')
    @alone = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'Alone')
    SequentialTaskIssue.create!(issue_id: @kid.id, branched_from_issue_id: @top.id, position: 1)
    @request.session[:user_id] = 2
  end

  def test_an_issue_with_branches_shows_the_view_with_itself_at_the_top
    get :show, params: { id: @top.id }
    assert_select 'iframe.sq-root-frame[data-src*=?]', "root=#{@top.id}"
    assert_select 'iframe.sq-root-frame[data-src*=?]', 'sq_embed=1'
    assert_select 'iframe.sq-root-frame[src]', 0 # loaded when it is opened
    assert_select 'details.sq-root-view > summary'
    assert_select 'details.sq-root-view[open]', 0 # folded at first
  end

  def test_an_issue_without_branches_shows_nothing_extra
    get :show, params: { id: @alone.id }
    assert_select 'iframe.sq-root-frame', 0
  end

  def test_nothing_is_shown_when_the_module_is_off
    Project.find(1).disable_module!(:sequential_tasks)
    get :show, params: { id: @top.id }
    assert_select 'iframe.sq-root-frame', 0
  end
end
