# frozen_string_literal: true

# The points of the milestone row: grouping by date, position and the room for labels.
# Logic only.
require 'minitest/autorun'
require 'date'
require File.expand_path('../../lib/redmine_sequential_tasks/timeline_slots', __dir__)
require File.expand_path('../../lib/redmine_sequential_tasks/milestones', __dir__)

class MilestonesTest < Minitest::Test
  Milestones = RedmineSequentialTasks::Milestones

  # ten day slots, Nov 1 to Nov 10, 42 px each
  SLOTS = (0..9).map { |i| { start_date: Date.new(2026, 11, 1) + i, end_date: Date.new(2026, 11, 1) + i } }.freeze
  WIDTH = 42

  def entry(day, label, kind: :version, closed: false, issue_id: nil)
    { date: Date.new(2026, 11, day), kind: kind, label: label, title: "#{label} (#{day})", url: "/#{label}", closed: closed,
      issue_id: issue_id }
  end

  def layout(entries)
    Milestones.layout(entries, SLOTS, WIDTH)
  end

  def test_a_marker_is_placed_in_the_middle_of_its_day
    marker = layout([entry(3, 'a')]).first
    assert_in_delta (2 + 0.5) / 10, marker[:frac], 1e-9
    assert_in_delta 2.5 * WIDTH, marker[:x], 1e-9
  end

  def test_markers_are_sorted_by_date
    assert_equal %w[b a c], layout([entry(5, 'a'), entry(2, 'b'), entry(8, 'c')]).map { |m| m[:label] }
  end

  def test_the_same_day_becomes_one_marker_with_every_label_and_title
    markers = layout([entry(4, 'v1'), entry(4, 'review', kind: :issue)])
    assert_equal 1, markers.size
    assert_equal 'v1 / review', markers.first[:label]
    assert_equal ['v1 (4)', 'review (4)'], markers.first[:titles]
    assert_equal :version, markers.first[:kind], 'the first entry decides the look and the link'
    assert_equal '/v1', markers.first[:url]
  end

  def test_a_marker_is_closed_only_when_all_its_entries_are
    assert layout([entry(4, 'a', closed: true), entry(4, 'b', closed: true)]).first[:closed]
    refute layout([entry(4, 'a', closed: true), entry(4, 'b')]).first[:closed]
  end

  def test_dates_outside_the_slots_are_dropped
    assert_empty layout([entry(3, 'a').merge(date: Date.new(2026, 10, 31)), entry(3, 'b').merge(date: Date.new(2026, 11, 11))])
  end

  def test_the_label_may_use_the_room_up_to_the_next_marker
    markers = layout([entry(2, 'a'), entry(6, 'b')])
    gap = markers[1][:x] - markers[0][:x]
    assert_in_delta gap - Milestones::MARKER_WIDTH, markers[0][:max_label], 1e-9
  end

  def test_the_last_label_may_use_the_room_up_to_the_end
    marker = layout([entry(9, 'a')]).first
    assert_in_delta SLOTS.size * WIDTH - marker[:x] - Milestones::MARKER_WIDTH, marker[:max_label], 1e-9
  end

  def test_a_label_never_has_negative_room
    assert layout([entry(2, 'a'), entry(3, 'b')]).all? { |m| m[:max_label] >= 0 }
  end

  def test_no_entries_no_markers
    assert_empty layout([])
  end

  def test_a_marker_lists_the_ids_of_its_issues_only
    markers = layout([entry(4, 'v1'), entry(4, 'a', kind: :issue, issue_id: 11), entry(4, 'b', kind: :issue, issue_id: 12)])
    assert_equal [11, 12], markers.first[:issue_ids]
    assert_equal [], layout([entry(4, 'v1')]).first[:issue_ids]
  end
end
