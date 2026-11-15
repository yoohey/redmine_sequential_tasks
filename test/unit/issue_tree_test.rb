# frozen_string_literal: true

# Branched issues directly under their parent. Logic only.
require 'minitest/autorun'
require 'set'
require File.expand_path('../../lib/redmine_sequential_tasks/issue_tree', __dir__)

class IssueTreeTest < Minitest::Test
  Item = Struct.new(:id, :parent_id)

  def flatten(items)
    RedmineSequentialTasks::IssueTree.flatten(items, &:parent_id).map { |item, level| [item.id, level] }
  end

  def test_branches_follow_their_parent_with_their_level
    items = [Item.new(1), Item.new(2, 1), Item.new(3), Item.new(4, 2)]
    assert_equal [[1, 0], [2, 1], [4, 2], [3, 0]], flatten(items)
  end

  def test_the_order_of_siblings_is_the_order_given
    items = [Item.new(5), Item.new(7, 5), Item.new(6, 5)]
    assert_equal [[5, 0], [7, 1], [6, 1]], flatten(items)
  end

  def test_an_issue_whose_parent_is_not_in_the_list_is_a_top_level_row
    items = [Item.new(2, 99), Item.new(3, 2)]
    assert_equal [[2, 0], [3, 1]], flatten(items)
  end

  def test_nothing_is_lost_or_repeated
    items = [Item.new(1), Item.new(2, 1), Item.new(3, 1), Item.new(4, 3), Item.new(5, 42)]
    assert_equal items.map(&:id).sort, flatten(items).map(&:first).sort
  end
end
