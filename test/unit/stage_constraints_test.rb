# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# One stage per status and issue, one step per status and tracker setting (review A-14):
# checked by the models and, as a last line of defence, by unique indexes.
class StageConstraintsTest < ActiveSupport::TestCase
  def setup
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    @setting.steps.create!(status_id: 1, position: 1, default_duration_days: 2)
    @issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
  end

  def test_a_step_cannot_repeat_a_status_in_the_same_setting
    step = @setting.steps.build(status_id: 1, position: 2, default_duration_days: 1)
    assert !step.valid?
    assert step.errors[:status_id].any?
  end

  def test_the_same_status_is_fine_in_another_setting
    other = SequentialTaskSetting.create!(tracker_id: 2, enabled: true)
    assert other.steps.build(status_id: 1, position: 1, default_duration_days: 1).valid?
  end

  def test_a_stage_cannot_repeat_a_status_for_the_same_issue
    stage = @issue.issue_stages.first
    duplicate = @issue.issue_stages.build(status_id: stage.status_id, position: 9, stage_status: 'pending')
    assert !duplicate.valid?
    assert duplicate.errors[:status_id].any?
  end

  def test_the_database_refuses_duplicate_steps_even_without_validation
    step = @setting.steps.build(status_id: 1, position: 2, default_duration_days: 1)
    assert_raises(ActiveRecord::RecordNotUnique) { step.save!(validate: false) }
  end

  def test_the_database_refuses_duplicate_stages_even_without_validation
    stage = @issue.issue_stages.first
    duplicate = @issue.issue_stages.build(status_id: stage.status_id, position: 9, stage_status: 'pending')
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end
end
