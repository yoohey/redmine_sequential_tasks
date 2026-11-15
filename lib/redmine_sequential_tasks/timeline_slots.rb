# frozen_string_literal: true

require 'date'

module RedmineSequentialTasks
  # The columns of the timeline: one slot per day, week (Monday to Sunday) or month. Logic only (the texts come in
  # as arguments); it uses ActiveSupport date helpers, so its test runs in the Redmine test container.
  module TimelineSlots
    SLOT_WIDTH = { 'days' => 42, 'weeks' => 136, 'months' => 190 }.freeze # px per slot
    PADDING = { 'days' => [7, 14], 'weeks' => [14, 28], 'months' => [30, 60] }.freeze # days before today, after today

    module_function

    # zoom      - 'days', 'weeks' or 'months'
    # min_date, max_date - the range the planned stages cover
    # today     - Date
    # day_names, month_names - abbreviated names indexed by wday and month number
    # week_label - ->(first_day) { text }
    # Returns [start_date, end_date, slots]. A slot is a Hash: start_date, end_date, label, sub_label, is_today,
    # is_weekend (a non-working day of Redmine's setting "non-working days", like Redmine's Gantt; not simply Saturday
    # and Sunday, so that the shading agrees with the working days the plan is counted in) and boundary (how strong the line after the slot is: :strong at a month change (days, weeks) or a
    # year change (months), :medium at a week change (days), nil otherwise).
    def build(zoom, min_date, max_date, today, day_names:, month_names:, week_label:)
      before, after = PADDING.fetch(zoom)
      start_date = [min_date, today - before].min
      end_date = [max_date, today + after].max
      case zoom
      when 'weeks'
        start_date = start_date.beginning_of_week(:monday)
        end_date = end_date.end_of_week(:monday)
      when 'months'
        start_date = start_date.beginning_of_month
        end_date = end_date.end_of_month
      end

      slots = case zoom
              when 'days' then day_slots(start_date, end_date, today, day_names)
              when 'weeks' then week_slots(start_date, end_date, today, week_label)
              else month_slots(start_date, end_date, today, month_names)
              end
      mark_boundaries(slots, zoom)
      [start_date, end_date, slots]
    end

    # Where a date is over the dates: 0..1 (the middle of its day, in proportion inside a week or month slot), or
    # nil when it is outside the slots
    def position(slots, date)
      idx = slots.index { |s| s[:start_date] <= date && date <= s[:end_date] }
      return nil unless idx

      slot = slots[idx]
      length = (slot[:end_date] - slot[:start_date]).to_i + 1
      (idx + (((date - slot[:start_date]).to_f + 0.5) / length)) / slots.size
    end

    # The horizontal extent of the days from..to (whole days) over the dates, as [left, right] fractions 0..1, cut at
    # the edges of the slots; nil when the range is entirely outside
    def span(slots, from, to)
      return nil if to < slots.first[:start_date] || from > slots.last[:end_date]

      [edge(slots, [from, slots.first[:start_date]].max, 0), edge(slots, [to, slots.last[:end_date]].min, 1)]
    end

    # The fraction at the start (0) or the end (1) of a day
    def edge(slots, date, day_part)
      idx = slots.index { |s| s[:start_date] <= date && date <= s[:end_date] }
      slot = slots[idx]
      length = (slot[:end_date] - slot[:start_date]).to_i + 1
      (idx + (((date - slot[:start_date]).to_f + day_part) / length)) / slots.size
    end

    def day_slots(start_date, end_date, today, day_names)
      (start_date..end_date).map do |d|
        { start_date: d, end_date: d, label: d.strftime('%m/%d'), sub_label: day_names[d.wday],
          is_today: d == today, is_weekend: !WorkingDayCalculator.working_day?(d) }
      end
    end

    def week_slots(start_date, end_date, today, week_label)
      slots = []
      cur = start_date
      while cur <= end_date
        last = cur + 6
        slots << { start_date: cur, end_date: last, label: week_label.call(cur), sub_label: "W#{cur.cweek}",
                   is_today: (cur..last).cover?(today), is_weekend: false }
        cur += 7
      end
      slots
    end

    def month_slots(start_date, end_date, today, month_names)
      slots = []
      cur = start_date
      while cur <= end_date
        last = cur.end_of_month
        slots << { start_date: cur, end_date: last, label: cur.strftime('%Y/%m'), sub_label: month_names[cur.month],
                   is_today: (cur..last).cover?(today), is_weekend: false }
        cur = last + 1
      end
      slots
    end

    def mark_boundaries(slots, zoom)
      slots.each_with_index do |slot, i|
        nxt = slots[i + 1]
        slot[:boundary] = nxt && boundary(zoom, slot[:start_date], nxt[:start_date])
      end
    end

    def boundary(zoom, from, to)
      case zoom
      when 'days'
        if to.month != from.month then :strong
        elsif to.monday? then :medium
        end
      when 'weeks'
        :strong if (to + 3).month != (from + 3).month # a week belongs to the month of its Thursday
      else
        :strong if to.year != from.year
      end
    end
  end
end
