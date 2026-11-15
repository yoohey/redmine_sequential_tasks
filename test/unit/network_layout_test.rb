# frozen_string_literal: true

# A prototype: which lane each phase gets so that the main flow stays
# on one lane and the parallel ones go under it. Logic only.
require 'minitest/autorun'
require 'date'
require File.expand_path('../../lib/redmine_sequential_tasks/network_layout', __dir__)

class NetworkLayoutTest < Minitest::Test
  Layout = RedmineSequentialTasks::NetworkLayout

  def node(id, from, to)
    { id: id, start: Date.parse(from), end: Date.parse(to) }
  end

  # The user's example: 1 -> 2 -> (3, 4) -> 5 -> (6, 8), and 7 (independent) -> 5
  def example
    nodes = [node(1, '2026-11-02', '2026-11-06'), node(2, '2026-11-09', '2026-11-13'), node(3, '2026-11-16', '2026-11-20'),
             node(4, '2026-11-16', '2026-11-20'), node(5, '2026-11-23', '2026-11-27'), node(6, '2026-11-30', '2026-12-04'),
             node(7, '2026-11-10', '2026-11-20'), node(8, '2026-11-30', '2026-12-09')]
    edges = [[1, 2], [2, 3], [2, 4], [3, 5], [4, 5], [7, 5], [5, 6], [5, 8]]
    [nodes, edges]
  end

  def test_the_main_flow_stays_on_one_lane_and_the_parallel_ones_go_under_it
    lanes = Layout.lanes(*example)
    assert_equal [0, 0, 0, 0, 0], [1, 2, 3, 5, 8].map { |id| lanes[id] }
    assert_equal 1, lanes[4], 'the second one after 2 goes under the main flow'
    assert_equal 2, lanes[7], 'the independent one that overlaps both goes under them'
    assert_equal 1, lanes[6], 'of the two after 5, the one that ends earlier goes under the other'
  end

  def test_of_two_that_follow_the_same_phase_the_one_that_ends_later_keeps_the_top_lane
    nodes = [node(1, '2026-11-02', '2026-11-06'), node(2, '2026-11-09', '2026-11-13'), node(3, '2026-11-09', '2026-11-20')]
    lanes = Layout.lanes(nodes, [[1, 2], [1, 3]])
    assert_equal [0, 1], [lanes[3], lanes[2]], 'the longer one is the critical one'
  end

  def test_a_phase_that_comes_after_two_phases_of_the_main_flow_is_as_thick_as_their_lanes
    placed = Layout.layout(*example)
    assert_equal({ lane: 0, span: 2 }, placed[5], '5 comes after 3 and 4 (lanes 0 and 1)')
    assert_equal 1, placed[8][:span]
    assert_equal 1, placed[7][:span], 'the independent one does not widen 5'
    assert_equal({ lane: 0, span: 1 }, placed[2])
  end

  def test_the_lanes_under_a_thick_bar_are_not_used_by_others_at_that_time
    nodes, edges = example
    nodes << node(9, '2026-11-24', '2026-11-26') # lands during 5, which is two lanes thick
    placed = Layout.layout(nodes, edges)
    assert_operator placed[9][:lane], :>=, 2
  end

  def test_nothing_overlaps_in_a_lane
    nodes, edges = example
    placed = Layout.layout(nodes, edges)
    (0..3).each do |lane|
      here = nodes.select { |n| (placed[n[:id]][:lane]...(placed[n[:id]][:lane] + placed[n[:id]][:span])).cover?(lane) }
      here.sort_by { |n| n[:start] }.each_cons(2) { |a, b| assert_operator a[:end], :<, b[:start] }
    end
  end

  def test_without_relations_it_packs_like_the_band
    lanes = Layout.lanes([node(1, '2026-11-02', '2026-11-10'), node(2, '2026-11-05', '2026-11-12'), node(3, '2026-11-13', '2026-11-20')], [])
    assert_equal({ 1 => 0, 2 => 1, 3 => 0 }, lanes)
  end

  def test_a_loop_in_the_relations_does_not_stop_it
    lanes = Layout.lanes([node(1, '2026-11-02', '2026-11-06'), node(2, '2026-11-09', '2026-11-13')], [[1, 2], [2, 1]])
    assert_equal [1, 2], lanes.keys.sort
  end

  def test_the_state_of_a_phase_comes_from_itself
    today = Date.parse('2026-11-18')
    assert_equal :done, Layout.state(node(1, '2026-11-02', '2026-11-06'), closed: true, today: today)
    assert_equal :delayed, Layout.state(node(1, '2026-11-02', '2026-11-06'), closed: false, today: today)
    assert_equal :current, Layout.state(node(1, '2026-11-16', '2026-11-20'), closed: false, today: today)
    assert_equal :future, Layout.state(node(1, '2026-11-23', '2026-11-27'), closed: false, today: today)
  end
end
