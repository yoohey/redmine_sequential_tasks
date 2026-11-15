# frozen_string_literal: true

# Statistics of the time issues stay in a stage. Logic only.
require 'minitest/autorun'
require 'date'
require File.expand_path('../../lib/redmine_sequential_tasks/stage_stats', __dir__)

class StageStatsTest < Minitest::Test
  Stats = RedmineSequentialTasks::StageStats

  def test_the_median_of_an_odd_and_an_even_number_of_values
    assert_equal 3, Stats.median([5, 1, 3])
    assert_equal 2.5, Stats.median([1, 2, 3, 4])
    assert_nil Stats.median([])
  end

  def test_the_mean
    assert_equal 2.0, Stats.mean([1, 2, 3])
    assert_nil Stats.mean([])
  end

  def test_dwell_days_count_working_days_and_are_at_least_one
    assert_equal 4, Stats.dwell_days(Date.new(2026, 11, 2), Date.new(2026, 11, 5)) { |from, to| (to - from).to_i + 1 }
    assert_equal 1, Stats.dwell_days(Date.new(2026, 11, 7), Date.new(2026, 11, 8)) { |_from, _to| 0 }, 'a weekend visit still counts one day'
  end

  def test_a_summary_has_count_mean_median_and_the_share_over_plan
    summary = Stats.summarize([{ dwell: 1, plan: 2 }, { dwell: 3, plan: 2 }, { dwell: 5, plan: 2 }, { dwell: 2, plan: nil }])
    assert_equal 4, summary[:count]
    assert_equal 2.75, summary[:mean]
    assert_equal 2.5, summary[:median]
    assert_in_delta 2.0 / 3, summary[:overrun_rate], 1e-9, 'two of the three visits that have a plan ran over it'
  end

  def test_a_summary_without_visits_or_plans_has_nothing_to_say
    assert_equal({ count: 0, mean: nil, median: nil, overrun_rate: nil }, Stats.summarize([]))
    assert_nil Stats.summarize([{ dwell: 2, plan: nil }])[:overrun_rate]
  end

  def test_a_baseline_needs_enough_visits
    assert_nil Stats.baseline([1, 2])
    assert_equal({ median: 2, count: 3 }, Stats.baseline([1, 2, 9]))
  end

  def test_slowness_is_the_ratio_to_the_median_when_clearly_longer
    baseline = { median: 2, count: 5 }
    assert_equal 2.5, Stats.slowness(5, baseline)
  end

  def test_slowness_needs_a_ratio_of_one_and_a_half_and_two_days_more
    assert_nil Stats.slowness(2, { median: 1, count: 5 }), 'twice as long, but only one day more'
    assert_nil Stats.slowness(5, { median: 4, count: 5 }), 'only 1.25 times'
    assert_equal 3.0, Stats.slowness(3, { median: 1, count: 5 })
  end

  def test_no_slowness_without_a_baseline
    assert_nil Stats.slowness(10, nil)
  end

  def test_the_bottleneck_is_the_stage_with_the_biggest_median_over_its_standard
    stages = [{ key: :a, median: 3, standard: 3, count: 5 }, { key: :b, median: 8, standard: 4, count: 5 }, { key: :c, median: 6, standard: 3, count: 2 }]
    assert_equal :b, Stats.bottleneck(stages), 'c has the bigger ratio but too few visits'
  end

  def test_no_bottleneck_when_nothing_is_clearly_longer_than_its_standard
    assert_nil Stats.bottleneck([{ key: :a, median: 3, standard: 3, count: 5 }, { key: :b, median: 4, standard: 4, count: 5 }])
  end
end
