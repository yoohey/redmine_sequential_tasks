# frozen_string_literal: true

class SequentialTaskBranchesController < ApplicationController
  before_action :find_parent_issue
  before_action :authorize_add_issue

  def create
    # Position and default subject suffix: one past the highest existing branch number,
    # so deleting a branch never produces a duplicate
    branch_index = SequentialTaskIssue.where(branched_from_issue_id: @parent_issue.id).maximum(:position).to_i + 1

    # The Issue model validates that the tracker is enabled for the project
    # and that the assignee is assignable
    tracker = @project.trackers.find_by(id: params[:tracker_id]) || @parent_issue.tracker

    child_issue = Issue.new(project: @project, author: User.current, tracker: tracker,
                            status: tracker&.default_status || @parent_issue.status)
    # Through safe_attributes, so that the workflow's read-only fields are respected. The subject is made from the
    # parent's, so a private parent gives a private child (its subject must not become visible to everyone).
    child_issue.safe_attributes = {
      'subject' => params[:subject].presence || "#{@parent_issue.subject}_#{branch_index}",
      'assigned_to_id' => (params[:assigned_to_id].presence || @parent_issue.assigned_to_id).to_s,
      'start_date' => (params[:start_date].presence || SequentialTaskIssue.default_start_date(@parent_issue)).to_s,
      'is_private' => @parent_issue.is_private? ? '1' : '0'
    } # for User.current (a setter takes one argument)
    # A role that may not set "private" drops it silently: a private parent still gives a private child, since its
    # subject is made from the parent's (the safe side; review 2026-11-14)
    child_issue.is_private = true if @parent_issue.is_private?

    # Create the issue and its branch link together: either both exist or neither
    Issue.transaction do
      child_issue.save!
      SequentialTaskIssue.create!(
        issue_id: child_issue.id,
        branched_from_issue_id: @parent_issue.id,
        position: branch_index
      )
    end

    flash[:notice] = l('sequential_tasks.flash.branch_created', id: child_issue.id, subject: child_issue.subject)
    redirect_back_or_default issue_path(@parent_issue)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e # NotSaved: refused in a callback, e.g. no working day
    flash[:error] = l('sequential_tasks.flash.branch_failed', errors: e.record.errors.full_messages.join(', '))
    redirect_back_or_default issue_path(@parent_issue)
  end

  private

  def find_parent_issue
    @parent_issue = Issue.visible.find(params[:issue_id])
    @project = @parent_issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_add_issue
    deny_access unless User.current.allowed_to?(:add_issues, @project) && @project.module_enabled?(:sequential_tasks)
  end
end
