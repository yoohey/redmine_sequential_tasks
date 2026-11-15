# frozen_string_literal: true

# A PROTOTYPE, read-only: the issues that are tied to one issue by
# the relations "precedes / follows", as bars on a date axis in lanes, with the dependencies shown lightly.
class SequentialTaskNetworksController < ApplicationController
  helper :sequential_tasks
  menu_item :sequential_tasks
  before_action :find_project_by_project_id
  before_action :authorize

  MAX_ISSUES = 60
  ZOOMS = %w[weeks days months].freeze

  def show
    @today = User.current.today
    @zoom = ZOOMS.include?(params[:zoom]) ? params[:zoom] : 'weeks'
    @seed = params[:issue_id].to_s.match?(/\A\d+\z/) ? Issue.visible.find_by(id: params[:issue_id]) : nil
    return unless @seed

    ids, relations = connected(@seed.id)
    issues = Issue.visible.where(id: ids).includes(:status, :tracker).to_a
    @truncated = ids.size >= MAX_ISSUES
    @undated = issues.reject { |i| i.start_date && i.due_date }
    @issues = (issues - @undated).sort_by { |i| [i.start_date, i.due_date, i.id] }
    shown = @issues.map(&:id)
    @edges = relations.select { |from, to| shown.include?(from) && shown.include?(to) }

    nodes = @issues.map { |i| { id: i.id, start: i.start_date, end: i.due_date } }
    @placed = RedmineSequentialTasks::NetworkLayout.layout(nodes, @edges) # { id => { lane:, span: } }
    @states = @issues.to_h do |i|
      [i.id, RedmineSequentialTasks::NetworkLayout.state({ start: i.start_date, end: i.due_date }, closed: i.closed?, today: @today)]
    end
    @start_date, @end_date, @slots = RedmineSequentialTasks::TimelineSlots.build(
      @zoom, @issues.map(&:start_date).min || @today, @issues.map(&:due_date).max || @today, @today,
      day_names: I18n.t('date.abbr_day_names'), month_names: I18n.t('date.abbr_month_names'),
      week_label: ->(first_day) { l('sequential_tasks.table.week_label', from: first_day.strftime('%m/%d')) }
    )
    bar_styles = SequentialTaskSetting.pluck(:tracker_id, :bar_style).to_h
    @bar_style = bar_styles[@seed.tracker_id] || RedmineSequentialTasks::BarStyle::DEFAULT
  end

  private

  # The ids tied to the issue by "precedes" or "relates" (both directions, and on), and the "precedes" relations among
  # them as [from, to]; "relates" only brings the issue in (a phase that runs alongside: no order). It stops at MAX_ISSUES.
  def connected(seed_id)
    ids = [seed_id]
    frontier = [seed_id]
    pairs = []
    until frontier.empty? || ids.size >= MAX_ISSUES
      rows = IssueRelation.where(relation_type: [IssueRelation::TYPE_PRECEDES, IssueRelation::TYPE_RELATES])
                          .where('issue_from_id IN (:f) OR issue_to_id IN (:f)', f: frontier)
                          .pluck(:issue_from_id, :issue_to_id, :relation_type)
      pairs.concat(rows.select { |_, _, type| type == IssueRelation::TYPE_PRECEDES }.map { |from, to, _| [from, to] })
      frontier = rows.flat_map { |from, to, _| [from, to] }.uniq - ids
      ids.concat(frontier)
    end
    [ids.first(MAX_ISSUES), pairs.uniq]
  end
end
