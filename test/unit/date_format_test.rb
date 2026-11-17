# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# How dates are written on the screens: a full date follows Redmine's "Date format" setting (or the language's
# default), a short month and day follows the language.
class DateFormatTest < ActiveSupport::TestCase
  DF = RedmineSequentialTasks::DateFormat
  DAY = Date.new(2026, 11, 6)

  def teardown
    ::I18n.locale = :en
    Setting.date_format = ''
  end

  def test_the_short_date_follows_the_language
    ::I18n.locale = :ja
    assert_equal '11/06', DF.short(DAY)
    ::I18n.locale = :en
    assert_equal 'Nov 6', DF.short(DAY)
  end

  def test_the_full_date_follows_redmines_setting_or_the_language
    Setting.date_format = '%Y-%m-%d'
    assert_equal '2026-11-06', DF.full(DAY)
    Setting.date_format = ''
    ::I18n.locale = :ja
    assert_equal '2026/11/06', DF.full(DAY)
  end

  def test_the_year_and_month_follow_the_language
    ::I18n.locale = :ja
    assert_equal '2026/11', DF.year_month(DAY)
    ::I18n.locale = :en
    assert_equal 'Nov 2026', DF.year_month(DAY)
  end

  def test_no_date_gives_nil
    assert_nil DF.short(nil)
  end
end
