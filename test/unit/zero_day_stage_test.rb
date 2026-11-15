# frozen_string_literal: true

# A first stage of zero days: "filed, but nobody has picked it up". With the Redmine test
# helper: WorkingDayCalculator reads Redmine's Setting.
require File.expand_path('../../../../../test/test_helper', __FILE__)

class ZeroDayStageTest < ActiveSupport::TestCase
  Stage = Struct.new(:id, :position, :planned_start_date, :planned_end_date, :zero_day)

  def test_a_zero_day_stage_is_not_adjustable
    wait = Stage.new(1, 1, Date.new(2026, 11, 2), Date.new(2026, 11, 2), true)
    design = Stage.new(2, 2, Date.new(2026, 11, 2), Date.new(2026, 11, 3), false)
    rescheduler = RedmineSequentialTasks::StageRescheduler.new([wait, design], wait)
    refute rescheduler.adjustable?(wait)
    assert rescheduler.adjustable?(design)
  end

  def test_while_waiting_the_later_stages_can_still_be_adjusted_from_the_start_date
    wait = Stage.new(1, 1, Date.new(2026, 11, 2), Date.new(2026, 11, 2), true)
    design = Stage.new(2, 2, Date.new(2026, 11, 2), Date.new(2026, 11, 3), false)
    build = Stage.new(3, 3, Date.new(2026, 11, 4), Date.new(2026, 11, 5), false)
    schedule = RedmineSequentialTasks::StageRescheduler.new([wait, design, build], wait).call({ 2 => 3 })
    assert_equal [2, 3], schedule.map { |s| s.stage.position }
    assert_equal [Date.new(2026, 11, 2), Date.new(2026, 11, 4)], [schedule[0].start_date, schedule[0].end_date]
  end
end
