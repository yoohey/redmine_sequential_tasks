# frozen_string_literal: true

# The bars of the band under the milestone row: which lane a bar gets. Logic only.
require 'minitest/autorun'
require 'date'
require File.expand_path('../../lib/redmine_sequential_tasks/timeline_slots', __dir__)
require File.expand_path('../../lib/redmine_sequential_tasks/band', __dir__)

class BandTest < Minitest::Test
  Band = RedmineSequentialTasks::Band

  # twenty day slots, Nov 1 to Nov 20
  SLOTS = (0..19).map { |i| { start_date: Date.new(2026, 11, 1) + i, end_date: Date.new(2026, 11, 1) + i } }.freeze

  def bar(label, from, to)
    { label: label, start: Date.new(2026, 11, from), end: Date.new(2026, 11, to) }
  end

  def pack(bars, max_lanes: 5)
    Band.pack(bars, SLOTS, max_lanes: max_lanes)
  end

  def labels(lane)
    lane.map { |b| b[:label] }
  end

  def test_a_bar_gets_its_position_and_width_as_fractions
    result = pack([bar('a', 3, 6)])
    b = result[:lanes].first.first
    assert_in_delta 2.0 / 20, b[:left], 1e-9
    assert_in_delta 4.0 / 20, b[:width], 1e-9
    assert_equal 0, b[:lane]
  end

  def test_bars_that_do_not_overlap_share_a_lane
    result = pack([bar('a', 1, 3), bar('b', 5, 8)])
    assert_equal 1, result[:lanes].size
    assert_equal %w[a b], labels(result[:lanes].first)
  end

  def test_bars_that_overlap_get_their_own_lanes
    result = pack([bar('a', 1, 8), bar('b', 4, 10), bar('c', 6, 12)])
    assert_equal 3, result[:lanes].size
    assert_equal [%w[a], %w[b], %w[c]], result[:lanes].map { |l| labels(l) }
  end

  def test_a_bar_that_starts_the_day_after_another_ends_may_share_its_lane
    result = pack([bar('a', 1, 3), bar('b', 4, 6)])
    assert_equal 1, result[:lanes].size
  end

  def test_the_earliest_start_goes_first_and_the_longer_bar_wins_a_tie
    result = pack([bar('short', 2, 3), bar('late', 5, 6), bar('long', 2, 9)])
    assert_equal %w[long], labels(result[:lanes][0]), 'long and short start together: the longer takes lane 0'
    assert_equal %w[short late], labels(result[:lanes][1]), 'late fits after short in lane 1 (long still runs in lane 0)'
  end

  def test_bars_beyond_the_lanes_are_counted_not_shown
    result = pack([bar('a', 1, 9), bar('b', 1, 9), bar('c', 1, 9), bar('d', 1, 9)], max_lanes: 2)
    assert_equal 2, result[:lanes].size
    assert_equal 2, result[:overflow]
  end

  def test_a_bar_is_cut_at_the_edges
    b = pack([{ label: 'x', start: Date.new(2026, 10, 20), end: Date.new(2026, 12, 31) }])[:lanes].first.first
    assert_in_delta 0.0, b[:left], 1e-9
    assert_in_delta 1.0, b[:width], 1e-9
  end

  def test_a_bar_outside_the_slots_is_dropped
    result = pack([{ label: 'x', start: Date.new(2026, 12, 1), end: Date.new(2026, 12, 9) }])
    assert_equal [], result[:lanes]
    assert_equal 0, result[:overflow]
  end

  def test_nothing_in_nothing_out
    assert_equal({ lanes: [], overflow: 0 }, pack([]))
  end
end
