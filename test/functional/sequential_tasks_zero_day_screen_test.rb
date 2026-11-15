# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The wait before a ticket is picked up (a first stage of zero days) on the timeline and in the
# analysis. Redmine fixtures: user 2 (jsmith) is a Manager of project 1.
class SequentialTasksZeroDayScreenTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [[1, 0], [2, 3], [3, 3]].each_with_index { |(s, d), i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: d) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all
    @issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.today - 5, subject: 'Waiting one')
    first = @issue.issue_stages.order(:position).first
    first.update_columns(actual_start_at: 3.days.ago)
    first.visits.update_all(entered_at: 3.days.ago)
    @request.session[:user_id] = 2
  end

  def row
    css_select("tr.issue-row[data-id='#{@issue.id}']").first
  end

  def test_the_zero_day_stage_has_no_bar_but_a_hatched_strip_and_a_chip_while_waiting
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    assert row
    assert_select row, '.sq-wait:not(.sq-wait-done)', 1
    assert_select row, '.sq-bar', 2, 'the two later stages only: the zero-day stage has no bar'
    assert_select row, '.sq-wait-chip', /3/
  end

  def test_after_it_is_picked_up_the_wait_stays_as_a_faint_strip_and_the_chip_goes
    @issue.reload
    @issue.init_journal(User.find(2))
    @issue.status_id = 2
    @issue.save!
    get :index, params: { project_id: 'ecookbook' }
    assert_select row, '.sq-wait.sq-wait-done', 1
    assert_select row, '.sq-wait-chip', 0
  end

  def test_the_lightning_point_of_a_waiting_issue_sits_at_the_left_end_of_the_next_bar
    get :index, params: { project_id: 'ecookbook' }
    assert row['data-edge'], 'the point is drawn at the left edge of the day, not its middle'
    @issue.reload
    @issue.init_journal(User.find(2))
    @issue.status_id = 2
    @issue.save!
    get :index, params: { project_id: 'ecookbook' }
    assert_nil row['data-edge']
  end

  def test_an_issue_that_has_not_started_yet_has_no_dent_in_the_lightning_line
    later = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.today + 10, subject: 'Not started')
    get :index, params: { project_id: 'ecookbook' }
    later_row = css_select("tr.issue-row[data-id='#{later.id}']").first
    assert later_row
    assert_nil later_row['data-edge'], 'it stands at today like the other not-started rows'
  end

  def test_the_row_stays_small
    get :index, params: { project_id: 'ecookbook' }
    assert_operator row.to_s.bytesize, :<, 3500
  end
end
