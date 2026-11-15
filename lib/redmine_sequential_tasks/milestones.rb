# frozen_string_literal: true

require 'date'

module RedmineSequentialTasks
  # The points of the milestone row under the date header. Logic only.
  module Milestones
    MARKER_WIDTH = 16 # the diamond and the gap before its label, in px

    module_function

    # entries     - Hashes: date (Date), kind (:version or :issue), label, title, url, closed
    # slots       - the slots of the timeline (see TimelineSlots)
    # slot_width  - px per slot
    # Returns the markers from left to right. Entries on the same day are one marker (the first entry decides the
    # kind and the link). A marker is a Hash: date, frac (0..1 over the dates), x (px), label (labels joined with
    # " / "), titles (one per entry), kind, url, closed (all of its entries are), issue_ids (the ids of its issues;
    # entries of kind :issue carry an issue_id), max_label (px the label may use before the next marker).
    # Dates outside the slots are dropped.
    def layout(entries, slots, slot_width)
      total = slots.size * slot_width
      placed = entries.filter_map do |entry|
        frac = TimelineSlots.position(slots, entry[:date])
        [frac, entry] if frac
      end
      markers = placed.group_by { |_, entry| entry[:date] }.sort_by(&:first).map do |date, pairs|
        group = pairs.map(&:last)
        frac = pairs.first.first
        { date: date, frac: frac, x: frac * total, label: group.map { |e| e[:label] }.join(' / '),
          titles: group.map { |e| e[:title] }, kind: group.first[:kind], url: group.first[:url],
          closed: group.all? { |e| e[:closed] }, issue_ids: group.filter_map { |e| e[:issue_id] } }
      end
      markers.each_with_index do |marker, i|
        limit = markers[i + 1] ? markers[i + 1][:x] : total
        marker[:max_label] = [limit - marker[:x] - MARKER_WIDTH, 0].max
      end
    end
  end
end
