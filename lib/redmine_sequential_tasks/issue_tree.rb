# frozen_string_literal: true

module RedmineSequentialTasks
  # Puts branched issues directly under their parent. Pure logic, so it can be tested without Redmine.
  module IssueTree
    module_function

    # issues - in the wanted order among siblings (the order of a parent's children and of the top level follows it)
    # The block gives the id of an issue's parent (nil for none). An issue whose parent is not in the list is a
    # top-level row. Returns [[issue, level], ...] in screen order (level 0 at the top).
    def flatten(issues)
      ids = issues.map(&:id).to_set
      children = Hash.new { |h, k| h[k] = [] }
      roots = []
      issues.each do |issue|
        parent_id = yield(issue)
        if parent_id && ids.include?(parent_id)
          children[parent_id] << issue
        else
          roots << issue
        end
      end

      rows = []
      walk = lambda do |issue, level|
        rows << [issue, level]
        children[issue.id]&.each { |child| walk.call(child, level + 1) }
      end
      roots.each { |root| walk.call(root, 0) }
      rows
    end
  end
end
