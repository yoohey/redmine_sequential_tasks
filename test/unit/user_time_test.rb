# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Dates are taken in the time zone of the current user (review A-7)
class UserTimeTest < ActiveSupport::TestCase
  def setup
    @user = User.find(2)
    User.current = @user
  end

  def teardown
    User.current = nil
  end

  def use_zone(name)
    @user.pref.update!(time_zone: name)
    User.current = User.find(2)
  end

  def test_a_late_evening_in_utc_is_the_next_day_in_tokyo
    use_zone('Tokyo')
    assert_equal Date.new(2026, 11, 2), RedmineSequentialTasks::UserTime.date_of(Time.utc(2026, 11, 1, 23, 30))
  end

  def test_the_same_instant_is_the_previous_day_far_to_the_west
    use_zone('Pacific/Pago_Pago')
    assert_equal Date.new(2026, 11, 1), RedmineSequentialTasks::UserTime.date_of(Time.utc(2026, 11, 2, 5, 0))
  end

  def test_nil_stays_nil
    assert_nil RedmineSequentialTasks::UserTime.date_of(nil)
  end
end
