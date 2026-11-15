# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# How assignee names are shown on the timeline and matrix: the plugin setting "name_order"
# (redmine = follow Redmine's user format, first_last, last_first). Fixture user 2 is John Smith.
class NameFormatTest < ActiveSupport::TestCase
  def setup
    @user = User.find(2)
  end

  def with_order(order)
    Setting.plugin_redmine_sequential_tasks = { 'name_order' => order }
  end

  def test_first_name_then_family_name
    with_order('first_last')
    assert_equal 'John Smith', RedmineSequentialTasks::NameFormat.name(@user)
  end

  def test_family_name_then_first_name
    with_order('last_first')
    assert_equal 'Smith John', RedmineSequentialTasks::NameFormat.name(@user)
  end

  def test_follow_redmines_own_user_format
    with_order('redmine')
    with_settings user_format: 'firstname' do # Redmine's own format "first name only" is not one of the plugin's two orders
      assert_equal 'John', RedmineSequentialTasks::NameFormat.name(User.find(2))
    end
  end

  def test_the_default_and_unknown_values_follow_redmine
    Setting.plugin_redmine_sequential_tasks = {}
    assert_equal 'redmine', RedmineSequentialTasks::NameFormat.order
    with_order('nonsense')
    assert_equal 'redmine', RedmineSequentialTasks::NameFormat.order
    assert_equal @user.name, RedmineSequentialTasks::NameFormat.name(@user)
  end

  def test_groups_keep_their_name
    with_order('last_first')
    group = Group.find(10)
    assert_equal group.name, RedmineSequentialTasks::NameFormat.name(group)
  end

  def test_nobody_and_the_anonymous_user
    with_order('last_first')
    assert_nil RedmineSequentialTasks::NameFormat.name(nil)
    anonymous = User.anonymous
    assert_equal anonymous.name, RedmineSequentialTasks::NameFormat.name(anonymous)
  end

  def test_a_missing_part_leaves_no_stray_space
    with_order('last_first')
    user = User.new(firstname: 'Prince', lastname: '')
    assert_equal 'Prince', RedmineSequentialTasks::NameFormat.name(user)
  end

  def test_a_precomputed_order_can_be_passed_in_loops
    with_order('last_first')
    assert_equal 'John Smith', RedmineSequentialTasks::NameFormat.name(@user, 'first_last')
  end
end
