# frozen_string_literal: true

module RedmineSequentialTasks
  # The visits of the stages of the issues a user may see in a project, with the days of each
  # stay. Used by the analysis screen and by the rows of the timeline and the matrix.
  class StageHistory
    # tracker_id, status_id (the stage), issue_id, stage_id, dwell (working days so far or in the end), plan (planned
    # working days of the issue for the stage, or nil), ongoing (the stay has not ended)
    Row = Struct.new(:tracker_id, :status_id, :issue_id, :stage_id, :dwell, :plan, :ongoing)

    def initialize(project, user: User.current)
      @project = project
      @user = user
      @today = user.today
      @days_off = WorkingDayCalculator.non_working_week_days
    end

    # days - only stays that ended in the last N days (and the ongoing ones); nil for all of them
    def rows(days: nil)
      scope = IssueStageVisit.joins(issue_stage: :issue).where(issues: { id: @project.issues.visible.select(:id) })
      scope = scope.where('issue_stage_visits.left_at IS NULL OR issue_stage_visits.left_at >= ?', days.days.ago) if days
      visits = scope.pluck('issues.tracker_id', 'issue_stages.status_id', 'issues.id', 'issue_stages.id', 'issue_stage_visits.entered_at',
                           'issue_stage_visits.left_at', 'issue_stages.planned_start_date', 'issue_stages.planned_end_date',
                           'issue_stages.zero_day', 'issue_stages.position')
      first_position = visits.group_by { |v| v[2] }.transform_values { |vs| vs.map(&:last).min }
      visits.filter_map do |tracker_id, status_id, issue_id, stage_id, entered, left, plan_from, plan_to, zero_day, position|
        from = local_date(entered)
        to = left ? local_date(left) : @today
        # The stage the issue was created in, with a start date still ahead then: the stay counts from the planned start
        # (the days before it are not time spent on the stage). Not yet started: not a stay at all.
        if position == first_position[issue_id] && plan_from && from < plan_from
          next if left.nil? && @today < plan_from
          from = plan_from if plan_from <= to
        end
        dwell = StageStats.dwell_days(from, to) { |a, b| working_days(a, b) }
        plan = plan_from && plan_to && !zero_day ? working_days(plan_from, plan_to) : nil # a wait has no plan to overrun
        Row.new(tracker_id, status_id, issue_id, stage_id, dwell, plan, left.nil?)
      end
    end

    # { [tracker_id, status_id] => { median:, count: } } from the finished stays (only where there are enough of them)
    def self.baselines(rows)
      rows.reject(&:ongoing).group_by { |r| [r.tracker_id, r.status_id] }.filter_map do |key, group|
        baseline = StageStats.baseline(group.map(&:dwell))
        [key, baseline] if baseline
      end.to_h
    end

    private

    def local_date(time)
      @user.convert_time_to_user_timezone(time).to_date
    end

    def working_days(from, to)
      return 0 if from > to

      (from..to).count { |d| !@days_off.include?(d.cwday) }
    end
  end
end
