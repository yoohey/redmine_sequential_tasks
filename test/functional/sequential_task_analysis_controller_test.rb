# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The analysis screen: how long issues stay in each stage. With no weekly days off, working
# days are calendar days. Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTaskAnalysisControllerTest < Redmine::ControllerTest
  tests SequentialTaskAnalysisController

  def setup
    Setting.non_working_week_days = []
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [[1, 2], [2, 3], [3, 2]].each_with_index { |(status, days), i| @setting.steps.create!(status_id: status, position: i + 1, default_duration_days: days) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    # Started a month ago: the visits below are after the planned start (before it, a stay does not count)
    @issues = 3.times.map { |i| Issue.generate!(project_id: 1, tracker_id: 1, subject: "issue #{i}", start_date: Date.today - 30) }
    IssueStageVisit.delete_all
    @request.session[:user_id] = 2
  end

  def visit(issue, status_id, from_days_ago, to_days_ago)
    stage = issue.issue_stages.find_by!(status_id: status_id)
    IssueStageVisit.create!(issue_stage: stage, entered_at: from_days_ago.days.ago, left_at: to_days_ago && to_days_ago.days.ago)
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  def cell(status_id, css)
    css_select("tr.sq-an-row[data-status='#{status_id}'] td.#{css}").first&.text&.squish
  end

  def history
    @issues.each { |i| visit(i, 1, 5, 2) }  # stage 1: four days each (2 planned days: over)
    @issues.each { |i| visit(i, 2, 1, 1) }  # stage 2: one day each (3 planned days)
  end

  def test_the_title_row_shows_when_the_page_was_made
    index
    assert_select '.sq-top .sq-asof', text: /UTC[+-]\d{2}:\d{2}/
  end

  def test_the_table_of_a_tracker_has_a_row_per_stage_with_its_figures
    history
    index
    assert_select 'table.sq-an', 1
    assert_equal '3', cell(1, 'sq-an-count')
    assert_equal '4', cell(1, 'sq-an-median')
    assert_equal '4.0', cell(1, 'sq-an-mean')
    assert_equal '2', cell(1, 'sq-an-standard')
    assert_equal '100%', cell(1, 'sq-an-overrun')
    assert_equal '1', cell(2, 'sq-an-median')
    assert_equal '0%', cell(2, 'sq-an-overrun')
  end

  def test_the_stage_that_stays_longest_over_its_standard_is_marked
    history
    index
    assert_select 'tr.sq-an-row.sq-an-bottleneck[data-status="1"]'
    assert_select 'tr.sq-an-row.sq-an-bottleneck', 1
  end

  def test_stages_with_too_few_visits_show_a_dash
    visit(@issues[0], 1, 3, 2)
    index
    assert_equal '1', cell(1, 'sq-an-count')
    assert_equal '–', cell(1, 'sq-an-median')
    assert_equal '–', cell(3, 'sq-an-median')
  end

  def test_issues_in_the_stage_now_are_counted_with_those_that_are_slower_than_usual
    history
    visit(@issues[0], 3, 1, nil) # stage 3, entered yesterday
    visit(@issues[1], 1, 12, nil) # still in stage 1 after twelve days: slower than the median of four
    index
    assert_equal '1', cell(3, 'sq-an-now')
    assert_equal '1', cell(1, 'sq-an-now')
    assert_equal '1', cell(1, 'sq-an-slow')
    assert_equal '0', cell(3, 'sq-an-slow')
  end

  # An issue filed with a start date ahead is in its first status from the start, but the stay counts from the planned
  # start; while the start date is still ahead, it is not in the stage yet
  def test_the_first_stage_counts_from_its_planned_start
    history
    early = @issues[0].issue_stages.find_by!(status_id: 1)
    IssueStageVisit.where(issue_stage_id: early.id).delete_all
    early.update_columns(planned_start_date: Date.today - 4)
    visit(@issues[0], 1, 6, 1) # entered six days ago, planned to start four days ago: four days, not six
    waiting = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'not started', start_date: Date.today + 3)
    visit(waiting, 1, 2, nil)  # filed two days ago, starts in three days
    index
    assert_equal '3', cell(1, 'sq-an-count')
    assert_equal '4.0', cell(1, 'sq-an-mean')
    assert_equal '0', cell(1, 'sq-an-now')
  end

  def test_the_period_keeps_only_visits_that_ended_recently
    @issues.each { |i| visit(i, 1, 100, 99) }
    @issues.each { |i| visit(i, 1, 5, 2) }
    index(days: '30')
    assert_equal '3', cell(1, 'sq-an-count')
    index
    assert_equal '6', cell(1, 'sq-an-count')
  end

  def test_the_tracker_can_be_chosen
    history
    index(tracker_id: '1')
    assert_select 'table.sq-an', 1
    index(tracker_id: '2')
    assert_select 'table.sq-an', 0
  end

  def test_visits_of_issues_the_user_may_not_see_are_not_counted
    history
    @issues[0].update_columns(is_private: true)
    @request.session[:user_id] = 3
    index
    assert_equal '2', cell(1, 'sq-an-count')
  end

  def test_the_screen_is_open_to_those_who_may_view_the_project
    @request.session[:user_id] = nil
    index
    assert_select 'table.sq-an'
  end

  def test_the_view_switch_has_the_analysis_and_marks_it
    index
    assert_select '.sq-seg a.sq-active[href*="/sequential_tasks/analysis"]'
    assert_select '.sq-seg a[href*="view=timeline"]'
    assert_select '.sq-seg a[href*="view=matrix"]'
  end

  def test_no_stages_no_tables
    SequentialTaskSetting.update_all(enabled: false)
    index
    assert_select 'table.sq-an', 0
    assert_select '.nodata'
  end

  def test_the_project_menu_keeps_the_sequential_tasks_tab_selected
    index
    assert_select '#main-menu a.selected', text: /#{Regexp.escape(I18n.t('sequential_tasks.menu.project'))}/
  end
end
