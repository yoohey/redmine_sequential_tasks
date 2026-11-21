# frozen_string_literal: true

module RedmineSequentialTasks
  module Patches
    module IssuePatch
      def self.included(base)
        base.class_eval do
          has_many :issue_stages, -> { order(:position) },
                   class_name: 'IssueStage',
                   foreign_key: 'issue_id',
                   dependent: :destroy

          has_one :sequential_task_issue,
                  class_name: 'SequentialTaskIssue',
                  foreign_key: 'issue_id',
                  dependent: :destroy

          has_many :branched_sequential_task_issues,
                   class_name: 'SequentialTaskIssue',
                   foreign_key: 'branched_from_issue_id',
                   dependent: :nullify

          has_many :branched_issues,
                   through: :branched_sequential_task_issues,
                   source: :issue

          before_create :set_default_dates_from_sequential_setting
          after_create :generate_sequential_task_stages
          after_save :update_sequential_stages_on_status_change
          before_save :validate_sequential_schedulable # may halt the save: no working day to build the plan on
          before_save :plan_sequential_date_changes # may halt the save; sets the due date before Redmine's own callbacks
          after_save :apply_sequential_plan
          before_save :prepare_sequential_tracker_change # moved to a sequential tracker
          after_save :regenerate_sequential_stages_on_tracker_change
        end
      end

      # Safe helper to get the parent issue this issue was branched from.
      # Returns nil when the parent is not visible to the current user.
      def branched_from_issue
        parent = sequential_task_issue&.branched_from_issue
        parent if parent&.visible?
      end

      # Issues branched from this issue that the current user is allowed to see
      def visible_branched_issues
        branched_issues.includes(:status, :assigned_to).select(&:visible?)
      end

      private

      # Before the save: an issue of a sequential tracker is not created, and its start or due date is not
      # changed, when there is no working day within about half a year (WorkingDayCalculator::SEARCH_DAYS) to build the
      # plan on -- every day set as non-working, or a calendar changed by another plugin. Refusing is safer than
      # looping forever or quietly counting every day.
      def validate_sequential_schedulable
        return unless new_record? || start_date_changed? || due_date_changed? || tracker_id_changed?

        setting = SequentialTaskSetting.find_by(tracker_id: tracker_id, enabled: true)
        return unless setting && setting.steps.any?

        calc = RedmineSequentialTasks::WorkingDayCalculator
        # far-away dates would make a plan (and a timeline) of thousands of days (review 2026-11-14)
        unless calc.date_in_range?(start_date) && calc.date_in_range?(due_date)
          errors.add(:base, l('sequential_tasks.flash.date_out_of_range', years: calc::DATE_RANGE_YEARS))
          throw(:abort)
        end
        return if calc.schedulable?(start_date || User.current.today)

        errors.add(:base, l('sequential_tasks.flash.no_working_day'))
        throw(:abort)
      end

      # Pre-calculate start_date and due_date based on sequential setting before saving the issue
      def set_default_dates_from_sequential_setting
        setting = SequentialTaskSetting.find_by(tracker_id: tracker_id, enabled: true)
        return unless setting && setting.steps.any?

        self.start_date ||= User.current.today
        self.start_date = RedmineSequentialTasks::WorkingDayCalculator.next_working_day(self.start_date)

        self.due_date = sequential_plan_end(setting, start_date) if due_date.blank?
      end

      # The end of the plan laid out from the standard days, starting on `start` (a working day)
      def sequential_plan_end(setting, start)
        standard = RedmineSequentialTasks::StandardDays.new(project_id) # the project's days, else the tracker's
        cur_start = start
        cur_end = cur_start
        setting.steps.each_with_index do |step, index|
          days = standard.days(tracker_id, step).to_i
          next if index.zero? && days <= 0 # a wait for somebody to pick the issue up: it uses no days

          cur_end = RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(cur_start, days)
          cur_start = RedmineSequentialTasks::WorkingDayCalculator.next_stage_start_date(cur_end)
        end
        cur_end
      end

      # an existing issue moved to a sequential tracker gets that tracker's stages, laid out from its start date
      # (today when it has none; on the next working day) with the standard days, as on creation; its due date is set to
      # the end of that plan (in the issue's history, so the issue and the plan agree). Any stages it had (from another
      # sequential tracker) are replaced. Moved away from a sequential tracker, its stages are kept (not shown; moving
      # back makes new ones). Before the save; the stages are written once it went through.
      def prepare_sequential_tracker_change
        @sequential_regenerate = false
        return if new_record? || !tracker_id_changed?

        setting = SequentialTaskSetting.find_by(tracker_id: tracker_id, enabled: true)
        return unless setting && setting.steps.any?

        new_start = RedmineSequentialTasks::WorkingDayCalculator.next_working_day(start_date || User.current.today)
        new_due = sequential_plan_end(setting, new_start)
        # The dates come from the plan; a date the workflow keeps read-only for the user is not changed behind it
        read_only = read_only_attribute_names(User.current)
        if (new_start != start_date && read_only.include?('start_date')) || (new_due != due_date && read_only.include?('due_date'))
          errors.add(:base, l('sequential_tasks.flash.tracker_dates_not_changeable'))
          throw(:abort)
        end
        self.start_date = new_start
        self.due_date = new_due
        @sequential_regenerate = true
      rescue RedmineSequentialTasks::WorkingDayCalculator::NoWorkingDay
        errors.add(:base, l('sequential_tasks.flash.no_working_day'))
        throw(:abort)
      end

      def regenerate_sequential_stages_on_tracker_change
        return unless @sequential_regenerate

        @sequential_regenerate = false
        ActiveRecord::Base.transaction do
          issue_stages.reload.each(&:destroy!)
          generate_sequential_task_stages
        end
        issue_stages.reset
      end

      # Automatically generate planned stages for issues with enabled sequential task settings
      def generate_sequential_task_stages
        setting = SequentialTaskSetting.find_by(tracker_id: tracker_id, enabled: true)
        return unless setting && setting.steps.any?

        cur_start = RedmineSequentialTasks::WorkingDayCalculator.next_working_day(start_date || User.current.today)

        standard = RedmineSequentialTasks::StandardDays.new(project_id)
        ActiveRecord::Base.transaction do
          setting.steps.each_with_index do |step, index|
            days = standard.days(tracker_id, step).to_i
            zero_day = index.zero? && days <= 0 # a wait for somebody to pick the issue up
            duration = [days, 1].max
            p_start = cur_start
            if zero_day
              p_end = p_start # a point: the next stage starts the same day
            else
              p_end = RedmineSequentialTasks::WorkingDayCalculator.calculate_end_date(p_start, duration)
              cur_start = RedmineSequentialTasks::WorkingDayCalculator.next_stage_start_date(p_end)
            end

            is_initial = (step.status_id == status_id)

            stage = issue_stages.create!(
              status_id: step.status_id,
              position: step.position,
              planned_start_date: p_start,
              planned_end_date: p_end,
              zero_day: zero_day,
              stage_status: is_initial ? 'in_progress' : 'pending',
              actual_start_at: is_initial ? Time.current : nil
            )
            stage.visits.create!(entered_at: stage.actual_start_at) if is_initial
          end
        end
      end

      # Editing the issue's start or due date directly -- on the issue form, through the REST API, or
      # when Redmine moves the issue for a preceding one (Issue#reschedule_on! sets both dates). One plan is made
      # here, BEFORE the save, from what changed:
      # - the start date, when it may move (StageRescheduler#start_changeable?): the plan starts there (on the next
      #   working day; the issue's start date is set to that day). With the due date unchanged, every stage keeps
      #   its days and the due date follows the new end; with the due date changed too, the stage before the due
      #   date (the slack) takes up the room between them;
      # - the due date only: the slack (or the only adjustable stage) ends on it. A due date on a non-working day
      #   is moved to the end of the plan (the working day before it), so the issue and the plan agree.
      # The due date is set on the issue itself (not written afterwards), so the change is in the issue's history,
      # Redmine's own callbacks (following issues, the parent) see the new date, and a due date the workflow keeps
      # read-only for the user is not changed behind it: the save is refused instead. A due date that cannot hold
      # the stages refuses the save too. The stages are written by apply_sequential_plan once the save went through.
      def plan_sequential_date_changes
        @sequential_plan = nil
        return if new_record? # creation: set_default_dates_from_sequential_setting / generate_sequential_task_stages
        return if tracker_id_changed? # a new tracker gets new stages (prepare_sequential_tracker_change)
        return unless start_date_changed? || due_date_changed?

        stages = issue_stages.order(:position).to_a
        return if stages.empty?

        summary = RedmineSequentialTasks::ProgressSummary.new(self, stages, User.current.today)
        rescheduler = RedmineSequentialTasks::StageRescheduler.new(stages, closed? ? nil : summary.schedule_anchor)
        return unless rescheduler.adjustable_any?

        calc = RedmineSequentialTasks::WorkingDayCalculator
        due_given = due_date_changed? && due_date.present?
        if start_date_changed? && start_date.present? && rescheduler.start_changeable?
          new_start = calc.next_working_day(start_date)
          self.start_date = new_start
          schedule = due_given ? rescheduler.call_fixed({}, start_date: new_start, target_end: due_date) : rescheduler.call({}, new_start)
          waits = stages.select(&:zero_day).map { |w| [w, new_start] } # a 0-day wait is a point at the start
        elsif due_given
          schedule = rescheduler.call_fixed({}, target_end: due_date)
          waits = []
        else
          return
        end
        return if schedule.empty?

        new_due = schedule.last.end_date
        if new_due != due_date
          if !due_given && !safe_attribute?('due_date', User.current)
            errors.add(:due_date, l('sequential_tasks.flash.due_not_changeable'))
            throw(:abort)
          end
          self.due_date = new_due
        end
        @sequential_plan = [schedule, waits]
      rescue RedmineSequentialTasks::StageRescheduler::CannotFit
        errors.add(:due_date, l('sequential_tasks.flash.cannot_fit_due_date'))
        throw(:abort)
      rescue RedmineSequentialTasks::WorkingDayCalculator::NoWorkingDay
        errors.add(:base, l('sequential_tasks.flash.no_working_day'))
        throw(:abort)
      end

      # Writes the stages planned by plan_sequential_date_changes, now that the save went through
      def apply_sequential_plan
        plan = @sequential_plan
        @sequential_plan = nil
        return unless plan

        schedule, waits = plan
        ActiveRecord::Base.transaction do
          waits.each { |stage, day| stage.update!(planned_start_date: day, planned_end_date: day) }
          schedule.each { |s| s.stage.update!(planned_start_date: s.start_date, planned_end_date: s.end_date) }
        end
      end

      # Updates stage states, actual timestamps and the visit history when the issue status changes.
      # Covers the timestamps, the visits, statuses outside the stages, an early close and skipped stages.
      def update_sequential_stages_on_status_change
        return unless saved_change_to_status_id?

        stages = issue_stages.order(:position).to_a
        return if stages.empty?

        _old_status_id, new_status_id = saved_change_to_status_id
        new_stage = stages.find { |s| s.status_id == new_status_id }

        # A status without a stage (e.g. Feedback) that is not closed: nothing changes.
        # The last stage stays in progress, with its visit open, as the place the issue got to.
        return if new_stage.nil? && !status&.is_closed?

        now = Time.current

        ActiveRecord::Base.transaction do
          update_sequential_visits(stages, new_stage, now)

          if new_stage
            stages.each do |stage|
              if stage.position < new_stage.position
                # Stages before the current one: entered ones are completed, never-entered ones are skipped
                stage.actual_start_at ? finish_sequential_stage(stage, now) : (stage.stage_status = 'skipped')
              elsif stage.position == new_stage.position
                stage.stage_status = 'in_progress'
                stage.actual_start_at ||= now
                stage.actual_end_at = nil
              else
                # Stages after the current one (also when rolling back or reopening) wait again.
                # actual_start_at is kept: it is the first entry.
                stage.stage_status = 'pending'
                stage.actual_end_at = nil
              end
              stage.save!
            end
          else
            # Closed without a stage of its own: finish the entered stages, skip the rest
            stages.each do |stage|
              next if %w[completed skipped].include?(stage.stage_status)

              if stage.stage_status == 'in_progress' || stage.actual_start_at
                finish_sequential_stage(stage, now)
              else
                stage.stage_status = 'skipped'
              end
              stage.save!
            end
          end
        end
      end

      # Completes a stage. Its end is the time it was last left (a stage that was rolled back from),
      # or now (the stage the issue is leaving).
      def finish_sequential_stage(stage, now)
        stage.stage_status = 'completed'
        stage.actual_start_at ||= now
        stage.actual_end_at ||= stage.visits.maximum(:left_at) || now
      end

      # Visit history: close the visit of the stage the issue leaves, open one for the stage it enters.
      # Entering the stage whose visit is still open (coming back from an out-of-stage status) adds nothing.
      def update_sequential_visits(stages, new_stage, now)
        ongoing = IssueStageVisit.ongoing.where(issue_stage_id: stages.map(&:id)).to_a
        keep = new_stage && ongoing.find { |v| v.issue_stage_id == new_stage.id }

        (ongoing - [keep].compact).each { |v| v.update!(left_at: now) }
        new_stage.visits.create!(entered_at: now) if new_stage && keep.nil?
      end
    end
  end
end
