# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Issues created through Redmine's REST API (POST /issues.json) get their stages and planned dates the same way as
# issues created on the screen. The use in mind: a separate system (a defect database
# and the like) files the issues, and the engineers only look at Redmine; the one who files and the one who picks it
# up are different people, so the first stage is often a wait (0 days, "受付待ち").
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1; tracker 1's default status is 1 (New).
class SequentialTasksApiIssueCreationTest < Redmine::ApiTest::Base
  def setup
    Setting.rest_api_enabled = '1'
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    Project.find(1).enable_module!(:sequential_tasks)
  end

  def steps(*days)
    days.each_with_index { |d, i| @setting.steps.create!(status_id: [1, 2, 3][i], position: i + 1, default_duration_days: d) }
  end

  def create_via_api(attrs = {})
    body = { issue: { project_id: 1, tracker_id: 1, subject: 'filed by the defect database' }.merge(attrs) }
    post '/issues.json', params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }.merge(credentials('jsmith'))
    assert_response :created
    Issue.find(ActiveSupport::JSON.decode(response.body)['issue']['id'])
  end

  def calc
    RedmineSequentialTasks::WorkingDayCalculator
  end

  def test_an_issue_filed_through_the_api_starts_with_the_wait
    steps(0, 3, 2) # the first stage is a wait for somebody to pick the issue up
    issue = create_via_api

    stages = issue.issue_stages.order(:position).to_a
    assert_equal 3, stages.size
    wait = stages.first
    assert wait.zero_day, 'the first stage is the wait'
    assert_equal 'in_progress', wait.stage_status, 'it is waiting now'
    assert_not_nil wait.actual_start_at
    assert_equal wait.planned_start_date, wait.planned_end_date, 'a wait is a point, it uses no days'
    assert_equal %w[pending pending], stages.drop(1).map(&:stage_status)

    start = calc.next_working_day(User.find(2).today)
    assert_equal start, issue.start_date
    assert_equal start, stages[1].planned_start_date, 'the first real stage starts the same day'
    assert_equal stages.last.planned_end_date, issue.due_date, 'the due date comes from the stages (3 + 2 working days)'
    assert_equal 5, calc.working_days_between(start, issue.due_date)
  end

  def test_an_issue_filed_through_the_api_without_a_wait_starts_at_once
    steps(2, 3)
    issue = create_via_api

    stages = issue.issue_stages.order(:position).to_a
    assert_equal 2, stages.size
    refute stages.first.zero_day
    assert_equal 'in_progress', stages.first.stage_status
    assert_equal stages.last.planned_end_date, issue.due_date
  end

  def test_a_start_date_sent_through_the_api_is_where_the_plan_begins
    steps(0, 3, 2)
    monday = Date.new(2030, 1, 7)
    issue = create_via_api(start_date: monday.to_s)

    stages = issue.issue_stages.order(:position).to_a
    assert_equal monday, issue.start_date
    assert_equal monday, stages[1].planned_start_date
    assert_equal calc.calculate_end_date(monday, 5), issue.due_date
  end

  def test_the_new_issue_is_on_the_projects_screen
    steps(0, 3, 2)
    issue = create_via_api

    get '/projects/ecookbook/sequential_tasks', headers: credentials('jsmith')
    assert_response :success
    assert_select "tr.issue-row[data-id='#{issue.id}']"
    assert_select "tr.issue-row[data-id='#{issue.id}'] .sq-wait-chip", 1 # the "受付待ち" chip
  end

  # no working day within half a year: the issue is refused, with the reason
  def test_an_issue_is_refused_through_the_api_without_any_working_day
    steps(0, 3, 2)
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    body = { issue: { project_id: 1, tracker_id: 1, subject: 'filed by the defect database' } }
    assert_no_difference -> { Issue.count } do
      post '/issues.json', params: body.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }.merge(credentials('jsmith'))
    end
    assert_response :unprocessable_content
    assert ActiveSupport::JSON.decode(response.body)['errors'].any?
  end
end
