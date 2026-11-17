# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The band of bars under the milestone row: versions, issues of the milestone trackers
# that last more than a day, and ordinary issues chained by Redmine's "precedes" relation.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTasksBandTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    Setting.plugin_redmine_sequential_tasks = { 'milestone_tracker_ids' => ['2'] }
    SequentialTaskIssue.delete_all
    # Redmine's own fixtures have versions, relations and issues of trackers 2 and 3 with dates around today
    IssueRelation.delete_all
    Version.update_all(effective_date: nil)
    Issue.where(tracker_id: [2, 3]).update_all(due_date: nil, start_date: nil)
    @row = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'a row')
    @request.session[:user_id] = 2
  end

  def teardown
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  def phase(subject, from, to, tracker: 2)
    Issue.generate!(project_id: 1, tracker_id: tracker, subject: subject, start_date: Date.today + from, due_date: Date.today + to)
  end

  def bars
    css_select('tr.sq-band-row a.sq-band-bar')
  end

  def test_a_version_with_a_start_and_a_due_date_is_a_bar_and_still_a_point
    version = Version.create!(project_id: 1, name: 'Release-1', effective_date: Date.today + 10)
    Issue.generate!(project_id: 1, tracker_id: 1, fixed_version_id: version.id, start_date: Date.today + 1)
    index
    assert_select "tr.sq-band-row a.sq-band-bar.sq-band-version[href='/versions/#{version.id}']"
    assert_select "tr.sq-ms-row a.sq-ms[href='/versions/#{version.id}']"
  end

  def test_an_issue_of_a_milestone_tracker_that_lasts_is_a_bar_not_a_point
    event = phase('Review week', 2, 6)
    index
    assert_select "tr.sq-band-row a.sq-band-bar.sq-band-issue[href='/issues/#{event.id}']"
    assert_select "a.sq-ms[href='/issues/#{event.id}']", 0
  end

  def test_an_issue_of_a_milestone_tracker_on_a_single_day_stays_a_point
    event = phase('Review day', 3, 3)
    index
    assert_select "a.sq-ms[href='/issues/#{event.id}']"
    assert_select 'tr.sq-band-row', 0
  end

  def test_ordinary_issues_chained_by_precedes_are_bars
    first = phase('Design', 1, 4, tracker: 3)
    second = phase('Build', 5, 9, tracker: 3)
    lonely = phase('Unrelated', 2, 8, tracker: 3)
    IssueRelation.create!(issue_from: first, issue_to: second, relation_type: 'precedes')
    index
    assert_select "tr.sq-band-row a.sq-band-bar.sq-band-chain[href='/issues/#{first.id}']"
    assert_select "tr.sq-band-row a.sq-band-bar.sq-band-chain[href='/issues/#{second.id}']"
    assert_select "a.sq-band-bar[href='/issues/#{lonely.id}']", 0
  end

  def test_issues_of_a_tracker_that_has_rows_are_not_bars_even_when_chained
    other = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'another row')
    IssueRelation.create!(issue_from: @row, issue_to: other, relation_type: 'precedes')
    index
    assert_select "a.sq-band-bar[href='/issues/#{@row.id}']", 0
  end

  def test_the_position_is_in_percent_of_the_dates
    phase('Review week', 2, 6)
    index
    style = bars.first['style']
    assert_match(/left: [\d.]+%/, style)
    assert_match(/width: [\d.]+%/, style)
  end

  def test_overlapping_bars_get_lanes_and_only_two_show_at_first
    4.times { |i| phase("Phase #{i}", 1 + i, 9 + i) }
    index
    assert_equal 4, css_select('tr.sq-band-row').size
    assert_equal 2, css_select('tr.sq-band-row.sq-band-extra').size, 'lanes 3 and 4 are hidden until the switch'
    assert_select 'input[type=checkbox][data-act=band-more]:not([checked])'
  end

  def test_with_two_lanes_there_is_no_switch
    2.times { |i| phase("Phase #{i}", 1 + i, 9 + i) }
    index
    assert_equal 2, css_select('tr.sq-band-row').size
    assert_select 'tr.sq-band-row.sq-band-extra', 0
    assert_select 'input[data-act=band-more]', 0
  end

  def test_at_most_five_lanes_and_the_rest_is_counted
    7.times { |i| phase("Phase #{i}", 1, 9) }
    index
    assert_equal 5, css_select('tr.sq-band-row').size
    assert_select 'label.sq-check[title*="2"]:has(input[data-act=band-more])' # the tip is on the label (the whole switch)
  end

  def test_the_header_cells_span_the_lanes_too
    phase('Review week', 2, 6)
    index
    # month tier, day tier, and one lane
    assert_select 'thead th.sq-th-issue[rowspan="3"]'
  end

  def test_the_bars_of_the_band_come_after_the_milestone_row
    phase('Review week', 2, 6)
    Version.create!(project_id: 1, name: 'Release-1', effective_date: Date.today + 10)
    index
    classes = css_select('thead tr').map { |tr| tr['class'].to_s }
    assert_operator classes.index { |c| c.include?('sq-ms-row') }, :<, classes.index { |c| c.include?('sq-band-row') }
  end

  def test_a_date_range_outside_the_visible_dates_is_not_shown
    phase('Far away', 400, 420)
    index
    assert_select 'tr.sq-band-row', 0
  end

  def test_an_issue_the_user_may_not_see_is_not_a_bar
    event = phase('Secret', 2, 6)
    event.update_columns(is_private: true)
    @request.session[:user_id] = 3
    index
    assert_select "a.sq-band-bar[href='/issues/#{event.id}']", 0
  end

  def test_the_matrix_has_no_band
    phase('Review week', 2, 6)
    index(view: 'matrix')
    assert_select 'tr.sq-band-row', 0
  end

  def test_no_bars_no_band
    index
    assert_select 'tr.sq-band-row', 0
    assert_select 'input[data-act=band-more]', 0
  end
end
