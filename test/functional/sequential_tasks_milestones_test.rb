# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The milestone row: versions with a due date and the issues of the milestone trackers.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook); tracker 2 has no stages here.
class SequentialTasksMilestonesTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    Setting.plugin_redmine_sequential_tasks = { 'milestone_tracker_ids' => ['2'] }
    SequentialTaskIssue.delete_all
    Issue.generate!(project_id: 1, tracker_id: 1, subject: 'a row')

    # Redmine's own fixtures have versions and issues of tracker 2 with dates around today: take them out of the way
    Version.update_all(effective_date: nil)
    Issue.where(tracker_id: 2).update_all(due_date: nil, start_date: nil)
    @version = Version.create!(project_id: 1, name: 'Release-1', effective_date: Date.today + 5)
    @event = Issue.generate!(project_id: 1, tracker_id: 2, subject: 'Customer review', due_date: Date.today + 3)
    @request.session[:user_id] = 2
  end

  def teardown
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  def test_a_version_with_a_due_date_is_a_marker_that_links_to_it
    index
    assert_select "tr.sq-ms-row a.sq-ms.sq-ms-version[href='/versions/#{@version.id}']"
    assert_includes css_select("a.sq-ms[href='/versions/#{@version.id}']").first['title'], 'Release-1'
    assert_select "a.sq-ms[href='/versions/#{@version.id}'] span", text: 'Release-1'
  end

  def test_an_issue_of_a_milestone_tracker_is_a_marker_that_links_to_it
    index
    assert_select "tr.sq-ms-row a.sq-ms.sq-ms-issue[href='/issues/#{@event.id}']"
    assert_includes css_select("a.sq-ms[href='/issues/#{@event.id}']").first['title'], 'Customer review'
  end

  def test_the_start_date_is_used_when_there_is_no_due_date
    @event.update_columns(due_date: nil, start_date: Date.today + 4)
    index
    assert_select "a.sq-ms[href='/issues/#{@event.id}']"
  end

  def test_an_issue_of_another_tracker_is_not_a_marker
    Setting.plugin_redmine_sequential_tasks = {}
    index
    assert_select "a.sq-ms[href='/issues/#{@event.id}']", 0
    assert_select "a.sq-ms[href='/versions/#{@version.id}']"
  end

  def test_a_version_without_a_due_date_is_not_a_marker
    @version.update_columns(effective_date: nil)
    index
    assert_select "a.sq-ms[href='/versions/#{@version.id}']", 0
  end

  def test_a_date_outside_the_visible_range_is_not_a_marker
    @version.update_columns(effective_date: Date.today + 400)
    index
    assert_select "a.sq-ms[href='/versions/#{@version.id}']", 0
  end

  def test_there_is_no_row_without_markers
    @version.update_columns(effective_date: nil)
    @event.destroy
    index
    assert_select 'tr.sq-ms-row', 0
    assert_select 'input[data-act=ms-lines]', 0
  end

  def test_finished_things_are_dimmed
    @version.update!(status: 'closed')
    @event.update!(status_id: 5)
    index
    assert_select "a.sq-ms.sq-ms-closed[href='/versions/#{@version.id}']"
    assert_select "a.sq-ms.sq-ms-closed[href='/issues/#{@event.id}']"
  end

  def test_two_things_on_one_day_are_one_marker
    @event.update_columns(due_date: @version.effective_date)
    index
    assert_equal 1, css_select('tr.sq-ms-row a.sq-ms').size
    title = css_select('tr.sq-ms-row a.sq-ms').first['title']
    assert_includes title, 'Release-1'
    assert_includes title, 'Customer review'
  end

  def test_an_issue_the_user_may_not_see_is_not_a_marker
    @event.update_columns(is_private: true)
    @request.session[:user_id] = 3
    index
    assert_select "a.sq-ms[href='/issues/#{@event.id}']", 0
  end

  def test_the_matrix_has_no_milestone_row
    index(view: 'matrix')
    assert_select 'tr.sq-ms-row', 0
  end

  def test_the_vertical_lines_switch_is_off_and_markers_carry_their_position
    index
    assert_select 'input[type=checkbox][data-act=ms-lines]:not([checked])'
    assert css_select('a.sq-ms').all? { |m| m['data-f'].to_f.between?(0, 1) }
  end

  def test_the_header_cells_span_all_rows_of_the_header
    index
    # month tier, day tier and the milestone row
    assert_select 'thead th.sq-th-issue[rowspan="3"]'
    @version.update_columns(effective_date: nil)
    @event.destroy
    index
    assert_select 'thead th.sq-th-issue[rowspan="2"]'
  end

  # Several issues on one day: the marker opens Redmine's issue list of just those issues
  def test_a_marker_of_several_issues_links_to_the_list_of_those_issues
    other = Issue.generate!(project_id: 1, tracker_id: 2, subject: 'Second event', due_date: @event.due_date)
    third = Issue.generate!(project_id: 1, tracker_id: 2, subject: 'Third event', due_date: @event.due_date)
    index
    markers = css_select('tr.sq-ms-row a.sq-ms.sq-ms-issue')
    assert_equal 1, markers.size
    href = markers.first['href']
    assert_match %r{\A/projects/ecookbook/issues\?}, href
    query = Rack::Utils.parse_nested_query(URI(href).query)
    assert_equal [@event.id, other.id, third.id].sort.join(','), query['v']['issue_id'].first.split(',').map(&:to_i).sort.join(',')
    assert_equal '=', query['op']['issue_id']
    assert_equal '*', query['op']['status_id'], 'finished issues are listed too'
    assert_equal '1', query['set_filter']
  end

  def test_a_marker_of_one_issue_and_a_version_still_links_to_the_first
    @event.update_columns(due_date: @version.effective_date)
    index
    assert_select "tr.sq-ms-row a.sq-ms[href='/versions/#{@version.id}']"
  end
end
