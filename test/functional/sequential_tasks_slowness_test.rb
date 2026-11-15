# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# "Slower than usual" on the rows. With no weekly days off, working days are calendar days.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTasksSlownessTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = []
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all
    IssueStageVisit.delete_all # the fixtures and the new issues come with visits of their own
    @request.session[:user_id] = 2
  end

  def new_issue(subject)
    # Started a month ago: the visits are after the planned start (before it, a stay does not count)
    Issue.generate!(project_id: 1, tracker_id: 1, subject: subject, start_date: Date.today - 30)
  end

  def set_visits(issue, status_id, entered_days_ago, left_days_ago = nil)
    stage = issue.issue_stages.find_by!(status_id: status_id)
    stage.visits.delete_all
    IssueStageVisit.create!(issue_stage: stage, entered_at: entered_days_ago.days.ago, left_at: left_days_ago && left_days_ago.days.ago)
  end

  # three finished stays of one day in stage 1 (the usual)
  def usual_stay
    3.times { |i| set_visits(new_issue("done #{i}"), 1, 1, 1).issue_stage.issue.update_columns(status_id: 2) }
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook', show_closed: '1' }.merge(params)
    assert_response :success
  end

  def chip(issue)
    css_select("tr[data-id='#{issue.id}'] span.sq-sl").first
  end

  def test_an_issue_that_stays_much_longer_than_usual_gets_a_chip_with_the_ratio
    usual_stay
    slow = new_issue('slow one')
    set_visits(slow, 1, 5) # entered five days ago: six days now, the usual is one
    index
    assert_not_nil chip(slow)
    assert_match(/6\.0/, chip(slow).text)
    assert_includes chip(slow)['title'], '6'
  end

  def test_no_chip_without_enough_finished_stays_to_compare_with
    2.times { |i| set_visits(new_issue("done #{i}"), 1, 1, 1) }
    slow = new_issue('slow one')
    set_visits(slow, 1, 5)
    index
    assert_nil chip(slow)
  end

  def test_no_chip_when_only_a_little_longer
    usual_stay
    a_bit = new_issue('a bit longer')
    set_visits(a_bit, 1, 1) # two days now against a usual of one: twice, but only one day more
    index
    assert_nil chip(a_bit)
  end

  def test_the_state_filter_can_show_only_the_slow_ones
    usual_stay
    slow = new_issue('slow one')
    set_visits(slow, 1, 5)
    quick = new_issue('quick one')
    set_visits(quick, 1, 0)
    index(state: 'slow')
    assert_select "tr[data-id='#{slow.id}']"
    assert_select "tr[data-id='#{quick.id}']", 0
  end

  def test_finished_issues_get_no_chip
    usual_stay
    done = new_issue('finished')
    set_visits(done, 1, 9)
    done.update_columns(status_id: 5)
    index
    assert_nil chip(done)
  end

  def test_the_matrix_has_the_chip_too_and_rows_stay_small
    usual_stay
    slow = new_issue('slow one')
    set_visits(slow, 1, 5)
    index(view: 'matrix')
    assert_not_nil chip(slow)
    assert css_select('tr.issue-row').map { |r| r.to_s.bytesize }.max < 3500
  end
end
