# frozen_string_literal: true

module RedmineSequentialTasks
  # The bars of the band under the milestone row: which lane each bar gets. Logic only.
  module Band
    MAX_LANES = 5
    VISIBLE_LANES = 2 # the lanes shown at first; the others wait for the switch
    EPSILON = 1e-9

    module_function

    # entries - Hashes with start and end (Date) and whatever the screen needs (label, url, ...)
    # slots   - the slots of the timeline (see TimelineSlots)
    # Returns { lanes: [[bar, ...], ...], overflow: n }. A bar is its entry plus left, width (fractions over the
    # dates, cut at the edges) and lane. Bars go in order of start (the longer first when equal) into the first lane
    # where they fit; what does not fit in max_lanes lanes is counted in overflow. Ranges outside the slots are dropped.
    def pack(entries, slots, max_lanes: MAX_LANES)
      bars = entries.each_with_index.filter_map do |entry, i|
        left, right = TimelineSlots.span(slots, entry[:start], entry[:end])
        entry.merge(left: left, width: right - left, order: i) if left
      end
      bars.sort_by! { |bar| [bar[:left], -bar[:width], bar[:order]] }

      lane_ends = []
      lanes = []
      overflow = 0
      bars.each do |bar|
        lane = lane_ends.index { |lane_end| lane_end <= bar[:left] + EPSILON }
        if lane.nil?
          if lane_ends.size >= max_lanes
            overflow += 1
            next
          end
          lane = lane_ends.size
          lane_ends << 0.0
          lanes << []
        end
        lane_ends[lane] = bar[:left] + bar[:width]
        lanes[lane] << bar.merge(lane: lane)
      end
      { lanes: lanes, overflow: overflow }
    end
  end
end
