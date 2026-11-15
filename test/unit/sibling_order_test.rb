# frozen_string_literal: true

# the order among siblings. Pure logic, so it runs without the Redmine test DB.
require 'minitest/autorun'
require 'date'
require File.expand_path('../../lib/redmine_sequential_tasks/sibling_order', __dir__)

class SiblingOrderTest < Minitest::Test
  Order = RedmineSequentialTasks::SiblingOrder

  Row = Struct.new(:id, :position, :due_date, :updated_on, :delay_days)

  def row(id, position: nil, due: nil, updated: nil, delay: 0)
    Row.new(id, position, due, updated, delay)
  end

  def ids(rows) = rows.map(&:id)

  # --- sorting (manual and the three automatic kinds)

  def test_manual_order_follows_position_and_puts_rows_without_a_position_last_by_id
    rows = [row(5), row(2, position: 2), row(9, position: 1), row(3)]
    assert_equal [9, 2, 3, 5], ids(Order.sort(rows, 'manual'))
  end

  def test_manual_order_breaks_ties_by_id
    rows = [row(8, position: 1), row(4, position: 1)]
    assert_equal [4, 8], ids(Order.sort(rows, 'manual'))
  end

  def test_due_date_order_puts_issues_without_a_due_date_last
    rows = [row(1), row(2, due: Date.new(2026, 12, 5)), row(3, due: Date.new(2026, 12, 1))]
    assert_equal [3, 2, 1], ids(Order.sort(rows, 'due'))
  end

  def test_largest_delay_first
    rows = [row(1, delay: 0), row(2, delay: 7), row(3, delay: 3)]
    assert_equal [2, 3, 1], ids(Order.sort(rows, 'delay'))
  end

  def test_most_recently_updated_first
    rows = [row(1, updated: Time.utc(2026, 11, 1)), row(2, updated: Time.utc(2026, 11, 3)), row(3, updated: nil)]
    assert_equal [2, 1, 3], ids(Order.sort(rows, 'updated'))
  end

  def test_an_unknown_kind_is_the_manual_order
    assert_equal 'manual', Order.kind(nil)
    assert_equal 'manual', Order.kind('nonsense')
    assert_equal 'due', Order.kind('due')
  end

  # --- moving one row

  def test_move_before_another_sibling
    assert_equal [1, 3, 2, 4], Order.move([1, 2, 3, 4], 3, 2)
  end

  def test_move_down_before_a_later_sibling
    assert_equal [2, 3, 1, 4], Order.move([1, 2, 3, 4], 1, 4)
  end

  def test_move_to_the_end_without_a_target
    assert_equal [2, 3, 4, 1], Order.move([1, 2, 3, 4], 1, nil)
  end

  def test_moving_before_itself_changes_nothing
    assert_equal [1, 2, 3], Order.move([1, 2, 3], 2, 2)
  end

  def test_an_unknown_row_or_target_changes_nothing
    assert_nil Order.move([1, 2, 3], 9, 1)
    assert_nil Order.move([1, 2, 3], 1, 9)
  end

  # --- renumbering: only the rows whose number changed are returned

  def test_renumber_gives_1_to_n_and_reports_only_changes
    current = { 1 => 1, 2 => 2, 3 => 3 }
    assert_equal({ 2 => 3, 3 => 2 }, Order.renumber([1, 3, 2], current))
  end

  def test_renumber_includes_rows_that_had_no_position_yet
    assert_equal({ 1 => 1, 2 => 2 }, Order.renumber([1, 2], {}))
  end
end
