# frozen_string_literal: true

# The project screens: the timeline and the matrix. The action only prepares data for the
# views (instance variables); the work is split into the steps below.
class SequentialTasksController < ApplicationController
  TIMELINE_YEARS = 2 # how far the timeline reaches from today, at most (review 2026-11-14)
  VIEWS = %w[timeline matrix].freeze
  ZOOMS = %w[days weeks months].freeze
  GROUPS = %w[none tracker assigned_to status version category].freeze
  STATE_FILTERS = %w[delayed ahead in_progress release_risk slow].freeze
  FAR_DATE = Date.new(9999, 12, 31) # sorts "no date" last

  # What the sort needs of an issue (see RedmineSequentialTasks::SiblingOrder)
  SortEntry = Struct.new(:id, :position, :due_date, :updated_on, :delay_days)

  before_action :find_project_by_project_id
  before_action :authorize

  def index
    read_display_params
    load_trackers_and_steps
    read_filter_params
    load_issues
    build_structure
    respond_to do |format|
      format.html do
        build_slots
        build_milestones
        build_band
      end
      # The matrix as CSV: one block per tracker, the same order and filters as the screen
      format.csv do
        blocks = @matrix_issues_by_tracker.filter_map do |tracker, rows|
          [tracker, @tracker_steps[tracker.id] || [], rows] if rows.any?
        end
        csv = RedmineSequentialTasks::MatrixCsv.new(blocks, stages_by_issue: @stages_by_issue, summaries: @summaries,
                                                    parents: @seq_issues.transform_values(&:branched_from_issue_id), today: @today,
                                                    encoding: (params[:encoding] == 'UTF-8' ? 'UTF-8' : nil)).generate
        send_data csv, type: 'text/csv; header=present', filename: "sequential_tasks-#{@project.identifier}-#{@today.strftime('%Y%m%d')}.csv"
      end
    end
  end

  private

  # ---- parameters -----------------------------------------------------------------------------

  # The value if it is one of the allowed ones, else the default
  def choice(value, allowed, default)
    allowed.include?(value) ? value : default
  end

  # A record id or 'none' from a parameter; anything that is not one of the candidates is ignored
  def id_or_none(value, candidates)
    value = value.presence
    value if value == 'none' || candidates.any? { |c| c.id.to_s == value }
  end

  def read_display_params
    @view = choice(params[:view], VIEWS, 'timeline')
    @view = 'matrix' if request.format.csv? # the CSV is the matrix
    @zoom = choice(params[:zoom], ZOOMS, 'days')
    @group_by = choice(params[:group_by], GROUPS, 'none')
    @tracker_filter = params[:tracker_id].presence&.to_i

    # Switches for finished and not-started issues: unfinished issues are shown, including not-started ones.
    # Filtering is done here, so the page does not carry the rows that are not shown.
    # The view with an issue at the top: the issue and its branches only, for the issue page. It has no
    # toolbar and no editing handles, and it shows finished issues too.
    @root_issue = params[:root].to_s.match?(/\A\d+\z/) ? @project.issues.visible.find_by(id: params[:root]) : nil
    @inline = @root_issue.present?
    @view = 'timeline' if @inline
    @show_closed = @inline || params[:show_closed] == '1'
    @show_pending = params[:show_pending] != '0'
    @today = User.current.today

    # Order among siblings. Handles are for the manual order and for users who may edit issues
    @sort = RedmineSequentialTasks::SiblingOrder.kind(params[:sort])
    @can_reorder = !@inline && @sort == 'manual' && User.current.allowed_to?(:edit_issues, @project)
    # The adjust mode of the timeline: drag the bars to change the plan, the same as the issue page's "adjust the schedule"
    @can_adjust = !@inline && @view == 'timeline' && User.current.allowed_to?(:edit_issues, @project) &&
                  RedmineSequentialTasks::WorkingDayCalculator.schedulable?(@today) # no working day, no plan
  end

  # The enabled trackers, and their stages (steps) with colors
  def load_trackers_and_steps
    settings = SequentialTaskSetting.where(tracker_id: @project.tracker_ids, enabled: true)
    @tracker_ids = settings.pluck(:tracker_id)
    @bar_styles = settings.pluck(:tracker_id, :bar_style).to_h # the look of the bars, per tracker
    @enabled_trackers = Tracker.where(id: @tracker_ids).order(:position)

    # Theme colors for stages by [tracker_id, status_id] and [tracker_id, position]
    @step_colors = {}
    @tracker_steps = Hash.new { |h, k| h[k] = [] }
    # Resolve the tracker from the already loaded settings to avoid one query per step
    tracker_id_by_setting_id = settings.pluck(:id, :tracker_id).to_h
    SequentialTaskStep.where(sequential_task_setting_id: tracker_id_by_setting_id.keys).includes(:status).order(:position).each do |step|
      tracker_id = tracker_id_by_setting_id[step.sequential_task_setting_id]
      color = step.color.presence
      color = nil unless color.to_s.match?(SequentialTaskStep::COLOR_FORMAT) # it goes into a style attribute
      @step_colors[[tracker_id, step.status_id]] = color
      @step_colors[[tracker_id, step.position]] = color
      @tracker_steps[tracker_id] << step
    end
  end

  # The filters of the toolbar; an unknown value is ignored
  def read_filter_params
    @versions = @project.shared_versions.to_a.sort
    @version_filter = id_or_none(params[:version_id], @versions)

    @categories = @project.issue_categories.to_a
    @category_filter = id_or_none(params[:category_id], @categories)

    # Finished and not-started issues have their own switches
    @state_filter = choice(params[:state].presence, STATE_FILTERS, nil)

    # The statuses that are a stage of an enabled tracker, in stage order
    @stage_status_ids = @tracker_steps.values.flatten.sort_by(&:position).map(&:status_id).uniq
    @stage_filter = choice(params[:stage].presence&.to_i, @stage_status_ids, nil)
  end

  # ---- issues ---------------------------------------------------------------------------------

  # Only issues the current user may see (role issue visibility, private issues), narrowed by the filters
  def scoped_issues
    scope = @project.issues.visible.where(tracker_id: @tracker_ids)
                    .includes(:tracker, :assigned_to, :status, :fixed_version, :category).order(:id)
    scope = scope.where(id: branch_family_ids(@root_issue.id)) if @inline
    scope = scope.where(category_id: @category_filter == 'none' ? nil : @category_filter.to_i) if @category_filter
    scope = scope.where(fixed_version_id: @version_filter == 'none' ? nil : @version_filter.to_i) if @version_filter
    scope
  end

  # The issue and every branch under it (branches of branches too). Each issue is visited once, so a loop in the
  # data cannot make this run forever.
  def branch_family_ids(root_id)
    ids = [root_id]
    frontier = [root_id]
    until frontier.empty?
      frontier = SequentialTaskIssue.where(branched_from_issue_id: frontier).pluck(:issue_id) - ids
      ids.concat(frontier)
    end
    ids
  end

  def load_issues
    all_issues = scoped_issues.to_a
    # Stages: only the columns the screens use, and no association preloading (the status names come from one
    # small table below); measured at about half the time and memory of includes(:status)
    stages_of_all = IssueStage.where(issue_id: all_issues.map(&:id))
                              .select(:id, :issue_id, :status_id, :position, :planned_start_date, :planned_end_date,
                                      :stage_status, :actual_start_at, :actual_end_at, :zero_day, :count_non_working)
                              .order(:position).group_by(&:issue_id)
    @status_names = IssueStatus.pluck(:id, :name).to_h
    summaries = all_issues.to_h do |issue|
      [issue.id, RedmineSequentialTasks::ProgressSummary.new(issue, stages_of_all[issue.id] || [], @today)]
    end
    @closed_total = summaries.values.count { |summary| summary.state == :closed }
    @pending_total = summaries.values.count { |summary| summary.state == :pending }

    @release = release_outlook(all_issues, summaries)
    @slowness = slowness_outlook(all_issues, summaries)
    @issues = all_issues.select { |issue| shown?(issue, summaries[issue.id]) }
    shown_ids = @issues.map(&:id)
    @summaries = summaries.slice(*shown_ids)
    @release = @release.slice(*shown_ids)
    @slowness = @slowness.slice(*shown_ids)
    @stages_by_issue = stages_of_all.slice(*shown_ids)

    # Branch relations and their numbers (the default name of a branch is "#{parent.subject}_#{count + 1}")
    @seq_issues = SequentialTaskIssue.where(issue_id: shown_ids).index_by(&:issue_id)
    @branch_counts = SequentialTaskIssue.where(branched_from_issue_id: shown_ids).group(:branched_from_issue_id).count

    @branch_progress = branch_progress(shown_ids)

    # Parents of branches that are not on this screen (finished, filtered out, other tracker): the screens name them
    outside_ids = @seq_issues.values.filter_map(&:branched_from_issue_id).uniq - shown_ids
    @outside_parents = Issue.visible.where(id: outside_ids).includes(:status).index_by(&:id)
  end

  # Will the issue make its release? For each open issue with a target version that has a due date and a
  # projected end: { date:, name:, margin: } (margin = days between the projected end and the release; negative is late)
  def release_outlook(issues, summaries)
    issues.each_with_object({}) do |issue, outlook|
      version = issue.fixed_version
      projected = summaries[issue.id].projected_end
      next unless version&.effective_date && projected

      name = version.project_id == @project.id ? version.name : version.to_s_with_project
      outlook[issue.id] = { date: version.effective_date, name: name, margin: (version.effective_date - projected).to_i }
    end
  end

  # Does the issue stay in its current stage much longer than usual? For each open issue in a stage that has
  # a baseline (the median of finished stays of its tracker, at least three of them): { ratio:, elapsed:, median:,
  # count:, stage: } (stage = the status name of the stage)
  def slowness_outlook(issues, summaries)
    rows = RedmineSequentialTasks::StageHistory.new(@project).rows
    baselines = RedmineSequentialTasks::StageHistory.baselines(rows)
    ongoing = rows.select(&:ongoing).index_by(&:stage_id)
    issues.each_with_object({}) do |issue, outlook|
      stage = summaries[issue.id].current_stage
      visit = stage && !summaries[issue.id].closed? ? ongoing[stage.id] : nil
      baseline = visit && baselines[[issue.tracker_id, stage.status_id]]
      ratio = baseline && RedmineSequentialTasks::StageStats.slowness(visit.dwell, baseline)
      next unless ratio

      outlook[issue.id] = { ratio: ratio, elapsed: visit.dwell, median: baseline[:median], count: baseline[:count], stage: stage.status_id }
    end
  end

  # How far are the branches of each shown parent? { parent_id => { total:, closed: } } over the branches the user may
  # see, whatever the screen hides
  def branch_progress(parent_ids)
    links = SequentialTaskIssue.where(branched_from_issue_id: parent_ids).pluck(:issue_id, :branched_from_issue_id).to_h # child => parent
    return {} if links.empty?

    closed = Issue.visible.where(id: links.keys).joins(:status).pluck('issues.id', 'issue_statuses.is_closed').to_h
    links.each_with_object({}) do |(child, parent), progress|
      next unless closed.key?(child)

      entry = (progress[parent] ||= { total: 0, closed: 0 })
      entry[:total] += 1
      entry[:closed] += 1 if closed[child]
    end
  end

  # The switches and the state and stage filters
  def shown?(issue, summary)
    state = summary.state
    return false if state == :closed && !@show_closed
    return false if state == :pending && !@show_pending
    return false if @state_filter == 'release_risk' && !(@release[issue.id] && @release[issue.id][:margin].negative?)
    return false if @state_filter == 'slow' && !@slowness[issue.id]
    return false if @state_filter && !%w[release_risk slow].include?(@state_filter) && state != @state_filter.to_sym
    return false if @stage_filter && summary.current_stage&.status_id != @stage_filter

    true
  end

  # ---- the structure of the view that is shown ------------------------------------------------

  # Siblings in the chosen order, branches directly under their parent: [[issue, level], ...]
  def tree(issue_list)
    sorted = RedmineSequentialTasks::SiblingOrder.sort(issue_list, @sort) do |issue|
      SortEntry.new(issue.id, @seq_issues[issue.id]&.position, issue.due_date, issue.updated_on, @summaries[issue.id].delay_days)
    end
    RedmineSequentialTasks::IssueTree.flatten(sorted) { |issue| @seq_issues[issue.id]&.branched_from_issue_id }
  end

  def build_structure
    @grouped_issues = {}
    @matrix_issues_by_tracker = {}
    if @view == 'matrix'
      # One table per tracker
      trackers = @tracker_filter.present? ? @enabled_trackers.select { |t| t.id == @tracker_filter } : @enabled_trackers
      by_tracker = @issues.group_by(&:tracker)
      trackers.each { |tracker| @matrix_issues_by_tracker[tracker] = tree(by_tracker[tracker] || []) }
    else
      groups.each { |key, list| @grouped_issues[key] = tree(list) }
    end
  end

  # The issues of the timeline in groups (a single group, key nil, when not grouped)
  def groups
    case @group_by
    when 'tracker' then @issues.group_by(&:tracker)
    when 'assigned_to' then @issues.group_by(&:assigned_to)
    when 'status' then @issues.group_by(&:status)
    when 'category' then @issues.group_by(&:category).sort_by { |c, _| c ? [0, c.name] : [1, ''] }.to_h
    when 'version' # in roadmap order (date, name); issues without a version last
      @issues.group_by(&:fixed_version).sort_by { |v, _| v ? [0, v.effective_date || FAR_DATE, v.name] : [1, FAR_DATE, ''] }.to_h
    else { nil => @issues }
    end
  end

  # ---- the columns of the timeline ------------------------------------------------------------

  def build_slots
    stages = @stages_by_issue.values.flatten
    # at most TIMELINE_YEARS either side of today: a stray far-away date must not make thousands of columns
    min_date = [stages.filter_map(&:planned_start_date).min || @today - 5, @today.prev_year(TIMELINE_YEARS)].max
    max_date = [stages.filter_map(&:planned_end_date).max || @today + 15, @today.next_year(TIMELINE_YEARS)].min
    @start_date, @end_date, @slots = RedmineSequentialTasks::TimelineSlots.build(
      @zoom, min_date, max_date, @today,
      day_names: I18n.t('date.abbr_day_names'), month_names: I18n.t('date.abbr_month_names'),
      week_label: ->(first_day) { l('sequential_tasks.table.week_label', from: first_day.strftime('%m/%d')) }
    )
  end

  # ---- the milestone row ---------------------------------------------------------------

  # Versions with a due date and issues of the milestone trackers, as points inside the visible dates
  def build_milestones
    @milestones = []
    return unless @view == 'timeline'

    @milestones = RedmineSequentialTasks::Milestones.layout(
      version_milestones + issue_milestones, @slots, RedmineSequentialTasks::TimelineSlots::SLOT_WIDTH.fetch(@zoom)
    )
    # Several issues on one day: the point opens Redmine's issue list of just those issues
    @milestones.each { |marker| marker[:url] = issue_list_path(marker[:issue_ids]) if marker[:issue_ids].size > 1 }
  end

  # Redmine's issue list of the given issues, all statuses
  def issue_list_path(ids)
    project_issues_path(@project, set_filter: 1, sort: 'id', f: %w[status_id issue_id],
                                  op: { status_id: '*', issue_id: '=' }, v: { issue_id: [ids.join(',')] })
  end

  def milestone_date_range
    @start_date..@end_date
  end

  def version_milestones
    visible_ids = Version.visible.where(id: @versions.map(&:id)).pluck(:id)
    @versions.select { |v| v.effective_date && milestone_date_range.cover?(v.effective_date) && visible_ids.include?(v.id) }.map do |version|
      name = version.project_id == @project.id ? version.name : version.to_s_with_project
      { date: version.effective_date, kind: :version, label: name, url: version_path(version),
        closed: version.closed? || version.completed?,
        title: l('sequential_tasks.milestone.version_title', name: name, date: version.effective_date.strftime('%Y/%m/%d'),
                                                              percent: version.completed_percent.round) }
    end
  end

  def issue_milestones
    tracker_ids = RedmineSequentialTasks::MilestoneSettings.tracker_ids
    return [] if tracker_ids.empty?

    # Issues that last (start before due) are bars of the band, not points
    @project.issues.visible.where(tracker_id: tracker_ids).includes(:status)
            .where('COALESCE(issues.due_date, issues.start_date) BETWEEN ? AND ?', @start_date, @end_date)
            .where('issues.start_date IS NULL OR issues.due_date IS NULL OR issues.start_date >= issues.due_date').map do |issue|
      date = issue.due_date || issue.start_date
      { date: date, kind: :issue, issue_id: issue.id, label: issue.subject, url: issue_path(issue), closed: issue.closed?,
        title: l('sequential_tasks.milestone.issue_title', id: issue.id, subject: issue.subject, date: date.strftime('%Y/%m/%d')) }
    end
  end

  # ---- the band of bars under the milestone row ----------------------------------------

  # Bars of versions, of milestone-tracker issues that last, and of ordinary issues chained by "precedes" (FS)
  def build_band
    @band = { lanes: [], overflow: 0 }
    return unless @view == 'timeline'

    @band = RedmineSequentialTasks::Band.pack(version_bars + milestone_issue_bars + chained_issue_bars, @slots)
  end

  def span_title(issue)
    l('sequential_tasks.milestone.span_title', id: issue.id, subject: issue.subject,
                                               from: issue.start_date.strftime('%Y/%m/%d'), to: issue.due_date.strftime('%Y/%m/%d'))
  end

  def issue_bar(issue, kind)
    { kind: kind, start: issue.start_date, end: issue.due_date, label: issue.subject, url: issue_path(issue),
      closed: issue.closed?, percent: issue.done_ratio, title: span_title(issue) }
  end

  def version_bars
    visible_ids = Version.visible.where(id: @versions.map(&:id)).pluck(:id)
    @versions.select { |v| v.effective_date && v.effective_date >= @start_date && visible_ids.include?(v.id) }.filter_map do |version|
      start = version.start_date
      next unless start && start < version.effective_date && start <= @end_date

      name = version.project_id == @project.id ? version.name : version.to_s_with_project
      { kind: :version, start: start, end: version.effective_date, label: name, url: version_path(version),
        closed: version.closed? || version.completed?, percent: version.completed_percent.round,
        title: l('sequential_tasks.milestone.version_title', name: name, date: version.effective_date.strftime('%Y/%m/%d'),
                                                              percent: version.completed_percent.round) }
    end
  end

  def dated_issues_in_range(scope)
    scope.visible.where.not(start_date: nil).where.not(due_date: nil)
         .where('issues.due_date >= ? AND issues.start_date <= ?', @start_date, @end_date)
  end

  def milestone_issue_bars
    tracker_ids = RedmineSequentialTasks::MilestoneSettings.tracker_ids
    return [] if tracker_ids.empty?

    dated_issues_in_range(@project.issues.where(tracker_id: tracker_ids)).where('issues.start_date < issues.due_date')
      .includes(:status).map { |issue| issue_bar(issue, :issue) }
  end

  # Ordinary issues (of trackers without rows on this screen) at an end of a "precedes" relation
  def chained_issue_bars
    skip_trackers = @tracker_ids + RedmineSequentialTasks::MilestoneSettings.tracker_ids
    candidates = dated_issues_in_range(@project.issues.where.not(tracker_id: skip_trackers)).includes(:status).to_a
    return [] if candidates.empty?

    ids = candidates.map(&:id)
    chained = IssueRelation.where(relation_type: IssueRelation::TYPE_PRECEDES)
                           .where('issue_from_id IN (:ids) OR issue_to_id IN (:ids)', ids: ids)
                           .pluck(:issue_from_id, :issue_to_id).flatten.to_set
    candidates.select { |issue| chained.include?(issue.id) }.map { |issue| issue_bar(issue, :chain) }
  end
end
