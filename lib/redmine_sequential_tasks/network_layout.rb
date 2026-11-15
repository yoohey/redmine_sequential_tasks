# frozen_string_literal: true

require 'date'

module RedmineSequentialTasks
  # A prototype: the phases of a plan as bars on a date axis, put in
  # lanes so that the main flow stays on one lane and the parallel ones go under it (no staircase). Logic only.
  module NetworkLayout
    module_function

    # nodes - Hashes with id, start and end (Date); edges - [[from_id, to_id], ...] (from precedes to)
    # Returns { id => { lane:, span: } } (span = how many lanes thick the bar is). The main flow (what follows the
    # earliest start) is placed first, in order of start, then the rest; so the independent ones go under the main
    # flow. A node that comes after two or more phases of the main flow is as thick as the lanes they stand on
    # (from the first to the last), when those lanes are free for its dates. Else it takes the lane of the
    # predecessor that ends last (the critical one) when that lane is free, then the lanes of its other
    # predecessors, else the first free lane.
    def layout(nodes, edges)
      preds = Hash.new { |h, k| h[k] = [] }
      succs = Hash.new { |h, k| h[k] = [] }
      edges.each { |from, to| preds[to] << from; succs[from] << to }
      by_id = nodes.to_h { |n| [n[:id], n] }

      main = main_flow(nodes, succs)
      # (when two start together, the one that ends later first: it is the critical one and keeps the top lane)
      ordered = nodes.sort_by { |n| [main.include?(n[:id]) ? 0 : 1, n[:start], -n[:end].jd, n[:id]] }

      placed = {}
      lanes = [] # the nodes in each lane
      ordered.each do |node|
        before = preds[node[:id]].select { |id| placed.key?(id) && by_id[id] }
        free = ->(l) { (lanes[l] || []).none? { |other| other[:start] <= node[:end] && node[:start] <= other[:end] } }

        lane = span = nil
        main_before = main.include?(node[:id]) ? before.select { |id| main.include?(id) } : []
        if main_before.size >= 2
          from = main_before.map { |id| placed[id][:lane] }.min
          to = main_before.map { |id| placed[id][:lane] + placed[id][:span] - 1 }.max
          if (from..to).all?(&free)
            lane = from
            span = to - from + 1
          end
        end
        unless lane
          candidates = before.sort_by { |id| [-by_id[id][:end].jd, id] }.map { |id| placed[id][:lane] }.uniq
          lane = candidates.find(&free) || lanes.each_index.find(&free) || lanes.size
          span = 1
        end
        span.times { |k| (lanes[lane + k] ||= []) << node }
        placed[node[:id]] = { lane: lane, span: span }
      end
      placed
    end

    # { id => lane } (the first lane of each bar)
    def lanes(nodes, edges)
      layout(nodes, edges).transform_values { |place| place[:lane] }
    end

    # The ids of what follows the node that starts first (itself included); a loop in the relations ends the walk
    def main_flow(nodes, succs)
      return [] if nodes.empty?

      first = nodes.min_by { |n| [n[:start], -(n[:end] - n[:start]).to_i, n[:id]] }
      seen = [first[:id]]
      queue = [first[:id]]
      until queue.empty?
        succs[queue.shift].each do |id|
          next if seen.include?(id)

          seen << id
          queue << id
        end
      end
      seen
    end

    # :done, :delayed, :current or :future, from the phase itself (it is not read from the chain)
    def state(node, closed:, today:)
      return :done if closed
      return :delayed if node[:end] < today
      return :current if node[:start] <= today

      :future
    end
  end
end
