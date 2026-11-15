# frozen_string_literal: true

module RedmineSequentialTasks
  # The trackers whose issues are shown as points in the milestone row (plugin setting "milestone_tracker_ids")
  module MilestoneSettings
    module_function

    def tracker_ids
      Array((Setting.plugin_redmine_sequential_tasks || {})['milestone_tracker_ids']).map(&:to_i).reject(&:zero?).uniq
    end
  end
end
