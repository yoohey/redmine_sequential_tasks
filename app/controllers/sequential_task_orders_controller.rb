# frozen_string_literal: true

# puts one issue before another among its siblings.
# Siblings: top-level issues among themselves, branches among those of the same parent.
# Issues that are filtered out of the screen are siblings too; they keep their relative place.
class SequentialTaskOrdersController < ApplicationController
  Entry = Struct.new(:id, :position)

  include RedmineSequentialTasks::ScreenEditing

  def update
    tracker_ids = SequentialTaskSetting.where(tracker_id: @project.tracker_ids, enabled: true).pluck(:tracker_id)
    scope = @project.issues.visible.where(tracker_id: tracker_ids)
    moving_id = params[:issue_id].to_i
    return render_404 unless scope.exists?(id: moving_id)

    records = SequentialTaskIssue.where(issue_id: scope.select(:id)).index_by(&:issue_id)
    parent_id = records[moving_id]&.branched_from_issue_id
    sibling_ids = scope.pluck(:id).select { |id| records[id]&.branched_from_issue_id == parent_id }
    current = RedmineSequentialTasks::SiblingOrder.sort(sibling_ids, 'manual') { |id| Entry.new(id, records[id]&.position) }

    before_id = params[:before_id].presence&.to_i
    new_order = RedmineSequentialTasks::SiblingOrder.move(current, moving_id, before_id)
    return head(:unprocessable_entity) unless new_order

    changes = RedmineSequentialTasks::SiblingOrder.renumber(new_order, new_order.to_h { |id| [id, records[id]&.position] })
    SequentialTaskIssue.transaction do
      changes.each do |id, position|
        record = records[id] || SequentialTaskIssue.new(issue_id: id, branched_from_issue_id: nil)
        record.update!(position: position)
      end
    end
    head :no_content
  end
end
