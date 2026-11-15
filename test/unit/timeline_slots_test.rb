# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The columns of the timeline. Runs in the Redmine test container (ActiveSupport dates).
class TimelineSlotsTest < ActiveSupport::TestCase
  Slots = RedmineSequentialTasks::TimelineSlots
  TODAY = Date.new(2026, 11, 11) # Wednesday
  DAYS = %w[Sun Mon Tue Wed Thu Fri Sat].freeze
  MONTHS = [nil] + %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]

  def build(zoom, min = TODAY, max = TODAY)
    Slots.build(zoom, min, max, TODAY, day_names: DAYS, month_names: MONTHS, week_label: ->(d) { d.strftime('%m/%d') })
  end

  def test_days_cover_a_week_before_and_two_weeks_after_today_at_least
    start_date, end_date, slots = build('days')
    assert_equal TODAY - 7, start_date
    assert_equal TODAY + 14, end_date
    assert_equal 22, slots.size
    assert_equal [TODAY], slots.select { |s| s[:is_today] }.map { |s| s[:start_date] }
  end

  def test_days_grow_to_cover_the_planned_range
    start_date, end_date, = build('days', TODAY - 30, TODAY + 40)
    assert_equal TODAY - 30, start_date
    assert_equal TODAY + 40, end_date
  end

  def test_weekends_are_marked_in_days
    Setting.non_working_week_days = %w[6 7]
    _, _, slots = build('days')
    assert_equal [6, 0], slots.select { |s| s[:is_weekend] }.map { |s| s[:start_date].wday }.uniq
  end

  # The shading follows Redmine's "non-working days" setting, the same days the plan is counted in
  def test_the_shaded_days_are_redmines_non_working_days
    Setting.non_working_week_days = %w[3] # Wednesday only
    _, _, slots = build('days')
    assert_equal [3], slots.select { |s| s[:is_weekend] }.map { |s| s[:start_date].wday }.uniq

    Setting.non_working_week_days = []
    _, _, slots = build('days')
    assert_empty slots.select { |s| s[:is_weekend] }, 'no non-working days: nothing is shaded'
  end

  def test_weeks_run_from_monday_to_sunday
    start_date, end_date, slots = build('weeks')
    assert start_date.monday?
    assert end_date.sunday?
    assert slots.all? { |s| s[:start_date].monday? && s[:end_date] == s[:start_date] + 6 }
    assert_equal 1, slots.count { |s| s[:is_today] }
    assert_match(/\AW\d+\z/, slots.first[:sub_label])
  end

  def test_months_run_from_the_first_to_the_last_day
    start_date, end_date, slots = build('months')
    assert_equal 1, start_date.day
    assert_equal end_date, end_date.end_of_month
    assert slots.all? { |s| s[:start_date].day == 1 && s[:end_date] == s[:start_date].end_of_month }
    assert_equal ['2026/11'], slots.select { |s| s[:is_today] }.map { |s| s[:label] }
  end

  def test_day_boundaries_are_strong_at_a_month_end_and_medium_at_a_week_end
    _, _, slots = build('days', TODAY, TODAY + 30)
    by_date = slots.to_h { |s| [s[:start_date], s[:boundary]] }
    assert_equal :strong, by_date[Date.new(2026, 11, 30)]
    assert_equal :medium, by_date[Date.new(2026, 11, 15)] # Sunday: the next day is Monday
    assert_nil by_date[Date.new(2026, 11, 12)]
    assert_nil slots.last[:boundary]
  end

  def test_week_boundaries_are_strong_where_the_month_changes_by_thursday
    _, _, slots = build('weeks', TODAY - 30, TODAY + 60)
    strong = slots.select { |s| s[:boundary] == :strong }.map { |s| s[:start_date] }
    assert strong.any?
    strong.each do |start|
      nxt = slots.find { |s| s[:start_date] == start + 7 }
      refute_equal (start + 3).month, (nxt[:start_date] + 3).month
    end
  end

  def test_month_boundaries_are_strong_at_a_year_end
    _, _, slots = build('months', TODAY, TODAY + 90) # Nov 2026 ... Feb 2027
    strong = slots.select { |s| s[:boundary] == :strong }.map { |s| s[:start_date] }
    assert_equal [Date.new(2026, 12, 1)], strong
  end

  # --- the position of a date (milestone row, lightning-like marks)

  def test_position_is_the_middle_of_a_day_in_a_day_slot
    _, _, slots = build('days')
    first = slots.first
    assert_in_delta 0.5 / slots.size, Slots.position(slots, first[:start_date]), 1e-9
    assert_in_delta (slots.size - 0.5) / slots.size, Slots.position(slots, slots.last[:end_date]), 1e-9
  end

  def test_position_is_proportional_inside_a_week_slot
    _, _, slots = build('weeks')
    monday = slots[2][:start_date]
    wednesday = monday + 2
    assert_in_delta (2 + 2.5 / 7) / slots.size, Slots.position(slots, wednesday), 1e-9
  end

  def test_position_of_a_date_outside_is_nil
    _, _, slots = build('days')
    assert_nil Slots.position(slots, slots.first[:start_date] - 1)
    assert_nil Slots.position(slots, slots.last[:end_date] + 1)
  end

  # --- the span of a date range (the bars of the band)

  def test_span_covers_whole_days_in_a_day_slot
    _, _, slots = build('days')
    from = slots[3][:start_date]
    to = slots[5][:start_date]
    left, right = Slots.span(slots, from, to)
    assert_in_delta 3.0 / slots.size, left, 1e-9
    assert_in_delta 6.0 / slots.size, right, 1e-9
  end

  def test_span_is_cut_at_the_edges
    _, _, slots = build('days')
    left, right = Slots.span(slots, slots.first[:start_date] - 30, slots.last[:end_date] + 30)
    assert_in_delta 0.0, left, 1e-9
    assert_in_delta 1.0, right, 1e-9
  end

  def test_span_outside_the_slots_is_nil
    _, _, slots = build('days')
    assert_nil Slots.span(slots, slots.first[:start_date] - 10, slots.first[:start_date] - 1)
    assert_nil Slots.span(slots, slots.last[:end_date] + 1, slots.last[:end_date] + 10)
  end

  def test_span_is_proportional_inside_a_week_slot
    _, _, slots = build('weeks')
    monday = slots[1][:start_date]
    left, right = Slots.span(slots, monday + 2, monday + 3) # Wednesday and Thursday
    assert_in_delta (1 + 2.0 / 7) / slots.size, left, 1e-9
    assert_in_delta (1 + 4.0 / 7) / slots.size, right, 1e-9
  end
end
