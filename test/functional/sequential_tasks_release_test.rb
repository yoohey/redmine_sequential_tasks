# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Will the issue make its release? The release is the due date of the target version.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTasksReleaseTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all
    Version.update_all(effective_date: nil)
    @today = User.find(2).today
    @request.session[:user_id] = 2
  end

  def issue_for(version, subject, planned_end_in:)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, subject: subject, fixed_version_id: version&.id)
    # three stages ending on the given day
    issue.issue_stages.order(:position).each_with_index do |stage, i|
      stage.update_columns(planned_start_date: @today + planned_end_in - 6 + (i * 2), planned_end_date: @today + planned_end_in - 4 + (i * 2),
                           stage_status: 'pending')
    end
    issue
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  def row(issue)
    "tr[data-id='#{issue.id}']"
  end

  def test_an_issue_that_ends_before_the_release_has_a_green_mark_and_no_chip
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    ok = issue_for(version, 'in time', planned_end_in: 6)
    index
    assert_select "#{row(ok)} i.sq-rel.sq-rel-ok"
    assert_select "#{row(ok)} .sq-rl", 0
    assert_includes css_select("#{row(ok)} i.sq-rel").first['title'], 'R1'
  end

  def test_an_issue_that_ends_after_the_release_has_a_red_mark_and_a_chip_with_the_days
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    late = issue_for(version, 'too late', planned_end_in: 13)
    index
    assert_select "#{row(late)} i.sq-rel.sq-rel-late"
    assert_select "#{row(late)} .sq-rl", text: /3/
  end

  def test_the_delay_is_added_to_the_end
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    issue = issue_for(version, 'slipping', planned_end_in: 10) # ends on the release day: just in time
    issue.issue_stages.order(:position).first.update_columns(stage_status: 'in_progress', planned_end_date: @today - 2)
    issue.update_columns(status_id: issue.issue_stages.order(:position).first.status_id)
    index
    assert_select "#{row(issue)} .sq-rl", 1, 'two days behind on the first stage pushes the end past the release'
  end

  def test_nothing_for_issues_without_a_version_or_a_due_date_or_when_finished
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    no_version = issue_for(nil, 'no version', planned_end_in: 6)
    undated = issue_for(Version.create!(project_id: 1, name: 'R2'), 'undated version', planned_end_in: 6)
    finished = issue_for(version, 'finished', planned_end_in: 6)
    finished.update!(status_id: 5)
    index(show_closed: '1')
    [no_version, undated, finished].each { |i| assert_select "#{row(i)} i.sq-rel", 0 }
  end

  def test_the_state_filter_can_show_only_the_issues_at_risk
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    ok = issue_for(version, 'in time', planned_end_in: 6)
    late = issue_for(version, 'too late', planned_end_in: 13)
    index(state: 'release_risk')
    assert_select row(late)
    assert_select row(ok), 0
    assert_select 'select[data-state] option[selected]', text: /./
  end

  def test_the_version_groups_count_the_issues_at_risk
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    issue_for(version, 'in time', planned_end_in: 6)
    issue_for(version, 'too late', planned_end_in: 13)
    issue_for(version, 'also late', planned_end_in: 20)
    index(group_by: 'version')
    header = css_select('tr.group-header-row').find { |h| h.text.include?('R1') }
    assert_not_nil header
    assert_select header, '.sq-gh-risk', text: /2/
  end

  def test_the_marks_are_in_the_timeline_only_and_rows_stay_small
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    issue_for(version, 'too late', planned_end_in: 13)
    index
    assert css_select('tr.issue-row').map { |r| r.to_s.bytesize }.max < 3500
    index(view: 'matrix')
    assert_select 'i.sq-rel', 0
  end

  # --- What the screen gives the script for moving an issue to another version

  def test_the_version_groups_are_drop_targets_in_the_reorder_setting
    version = Version.create!(project_id: 1, name: 'R1', effective_date: @today + 10)
    issue_for(version, 'x', planned_end_in: 6)
    index(group_by: 'version')
    assert_select '#sq-root[data-version-url]'
    assert_select 'tr.group-header-row[data-version]'
  end

  def test_other_groupings_and_users_who_may_not_edit_get_no_version_drop
    index(group_by: 'status')
    assert_select '#sq-root[data-version-url]', 0
    @request.session[:user_id] = nil
    index(group_by: 'version')
    assert_select '#sq-root[data-version-url]', 0
    assert_select 'tr.group-header-row[data-version]'
  end
end
