# frozen_string_literal: true

require 'date'

module RedmineSequentialTasks
  # The order among siblings: top-level issues among themselves, branches among those of the same parent.
  # Pure logic, so it can be tested without Redmine.
  module SiblingOrder
    KINDS = %w[manual due delay updated].freeze
    NO_POSITION = 2**31 # an issue that was never placed by hand comes after the placed ones

    module_function

    # The sort kind from a request parameter; anything unknown is the manual order
    def kind(value)
      KINDS.include?(value) ? value : 'manual'
    end

    # Sorts siblings. The block (optional) turns an element into something that responds to
    # #id, #position, #due_date, #updated_on and #delay_days.
    def sort(list, kind_name)
      kind_name = kind(kind_name)
      list.sort_by do |item|
        row = block_given? ? yield(item) : item
        key(kind_name, row)
      end
    end

    def key(kind_name, row)
      case kind_name
      when 'due'
        [row.due_date ? 0 : 1, row.due_date ? row.due_date.jd : 0, row.id]
      when 'delay'
        [-row.delay_days.to_i, row.id]
      when 'updated'
        [row.updated_on ? 0 : 1, row.updated_on ? -row.updated_on.to_f : 0, row.id]
      else
        [row.position || NO_POSITION, row.id]
      end
    end

    # ids: all siblings in their current order. Puts moving_id right before before_id (the end when
    # before_id is nil). Returns the new order, or nil when an id is not among the siblings.
    def move(ids, moving_id, before_id)
      return nil unless ids.include?(moving_id)
      return nil unless before_id.nil? || ids.include?(before_id)
      return ids.dup if before_id == moving_id

      rest = ids - [moving_id]
      at = before_id.nil? ? rest.size : rest.index(before_id)
      rest.insert(at, moving_id)
    end

    # ids in the wanted order, current: { id => stored position }. Returns { id => new position } (1..n)
    # for the rows whose stored position differs, so only those are written.
    def renumber(ids, current)
      changes = {}
      ids.each_with_index do |id, i|
        changes[id] = i + 1 unless current[id] == i + 1
      end
      changes
    end
  end
end
