# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Stage transitions on status change.
# Redmine fixture statuses: 1 New, 2 Assigned, 3 Resolved, 4 Feedback, 5 Closed (closed), 6 Rejected (closed).
# The tracker (Bug) gets three stages: New -> Assigned -> Resolved.
class IssuePatchTest < ActiveSupport::TestCase
  NEW = 1
  ASSIGNED = 2
  RESOLVED = 3
  FEEDBACK = 4
  CLOSED = 5
  REJECTED = 6

  def setup
    User.current = nil
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [NEW, ASSIGNED, RESOLVED].each_with_index do |status_id, i|
      setting.steps.create!(status_id: status_id, position: i + 1, default_duration_days: 2)
    end
    @issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: NEW)
  end

  def change_status(status_id)
    @issue.reload
    @issue.status_id = status_id
    @issue.save!
  end

  def stage(position)
    @issue.issue_stages.reload.find { |s| s.position == position }
  end

  def statuses
    (1..3).map { |p| stage(p).stage_status }
  end

  def visits(position)
    stage(position).visits.order(:id).to_a
  end

  def test_creation_generates_stages_and_opens_the_first_visit
    assert_equal %w[in_progress pending pending], statuses
    assert_not_nil stage(1).actual_start_at
    assert_equal 1, visits(1).size
    assert_nil visits(1).first.left_at
    assert_equal stage(1).actual_start_at, visits(1).first.entered_at
    assert_empty visits(2)
  end

  def test_forward_by_one_completes_the_previous_stage
    change_status(ASSIGNED)

    assert_equal %w[completed in_progress pending], statuses
    assert_not_nil stage(1).actual_end_at
    assert_nil stage(2).actual_end_at
    assert_not_nil visits(1).first.left_at
    assert_equal 1, visits(2).size
    assert_nil visits(2).first.left_at
  end

  def test_forward_jump_skips_the_stage_in_between_without_dates_or_visits
    change_status(RESOLVED)

    assert_equal %w[completed skipped in_progress], statuses
    assert_nil stage(2).actual_start_at
    assert_nil stage(2).actual_end_at
    assert_empty visits(2)
    assert_equal 1, visits(3).size
  end

  def test_rollback_keeps_the_history_and_adds_a_visit_on_reentry
    change_status(ASSIGNED)
    change_status(RESOLVED)
    first_end = stage(2).actual_end_at
    change_status(ASSIGNED)

    assert_equal %w[completed in_progress pending], statuses
    assert_nil stage(2).actual_end_at, 'the re-entered stage is not finished'
    assert_nil stage(3).actual_end_at
    assert_not_nil first_end
    assert_equal 2, visits(2).size
    assert_not_nil visits(2).first.left_at
    assert_nil visits(2).last.left_at
    assert_equal 1, visits(3).size, 'the first pass through stage 3 stays in the history'
    assert_not_nil visits(3).first.left_at
  end

  def test_rollback_into_a_skipped_stage_starts_it_and_records_the_visit
    change_status(RESOLVED)
    change_status(ASSIGNED)

    assert_equal %w[completed in_progress pending], statuses
    assert_not_nil stage(2).actual_start_at
    assert_equal 1, visits(2).size
    assert_nil visits(2).first.left_at
  end

  def test_status_without_a_stage_changes_nothing
    change_status(ASSIGNED)
    before = @issue.issue_stages.reload.map { |s| [s.stage_status, s.actual_start_at, s.actual_end_at] }
    change_status(FEEDBACK)

    assert_equal before, @issue.issue_stages.reload.map { |s| [s.stage_status, s.actual_start_at, s.actual_end_at] }
    assert_nil visits(2).first.left_at, 'the visit stays open while the issue waits in an out-of-stage status'
  end

  def test_returning_to_the_same_stage_does_not_open_a_second_visit
    change_status(ASSIGNED)
    change_status(FEEDBACK)
    change_status(ASSIGNED)

    assert_equal 1, visits(2).size
    assert_equal %w[completed in_progress pending], statuses
  end

  def test_leaving_from_an_out_of_stage_status_closes_the_open_visit_of_the_last_stage
    change_status(ASSIGNED)
    change_status(FEEDBACK)
    change_status(RESOLVED)

    assert_equal %w[completed completed in_progress], statuses
    assert_not_nil visits(2).first.left_at
    assert_equal 1, visits(3).size
  end

  def test_closing_in_the_middle_completes_the_current_stage_and_skips_the_rest
    change_status(ASSIGNED)
    change_status(CLOSED)

    assert_equal %w[completed completed skipped], statuses
    assert_not_nil stage(2).actual_end_at
    assert_nil stage(3).actual_start_at
    assert_empty visits(3)
    assert_nil IssueStageVisit.where(issue_stage_id: @issue.issue_stages.map(&:id), left_at: nil).first,
               'no visit stays open after closing'
  end

  def test_closing_at_the_first_stage_skips_the_others
    change_status(REJECTED)

    assert_equal %w[completed skipped skipped], statuses
  end

  def test_closing_a_stage_that_was_rolled_back_from_completes_it_with_the_time_it_was_left
    change_status(RESOLVED)
    change_status(ASSIGNED) # stage 3 is visited, then left again
    left_at = visits(3).first.left_at
    change_status(CLOSED)

    assert_equal 'completed', stage(3).stage_status
    assert_equal left_at.to_i, stage(3).actual_end_at.to_i
  end

  def test_reopening_after_an_early_close_resets_the_stages_after_the_current_one
    change_status(ASSIGNED)
    change_status(CLOSED)
    change_status(ASSIGNED)

    assert_equal %w[completed in_progress pending], statuses
    assert_nil stage(2).actual_end_at
    assert_equal 2, visits(2).size
  end

  # The default start date of a new issue is the user's today, not the server's (review A-7)
  def test_the_default_start_date_follows_the_users_time_zone
    zone = ['Pacific/Kiritimati', 'Pacific/Pago_Pago'].find { |z| Time.now.in_time_zone(z).to_date != Date.today }
    assert zone, 'one of the two zones has another date than the server'
    User.find(2).pref.update!(time_zone: zone)
    User.current = User.find(2)
    Setting.non_working_week_days = []
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: NEW, start_date: nil)
    assert_equal User.current.today, issue.start_date
  ensure
    User.current = nil
  end
end
