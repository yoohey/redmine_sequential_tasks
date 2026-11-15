# frozen_string_literal: true

module RedmineSequentialTasks
  # The matrix of the project screen as CSV: like the screen, one block per tracker (a
  # title row, a header row with that tracker's stages, the issues, then an empty row), in the order and with the
  # filters of the screen. Each stage has five columns: planned start / planned end / actual start / actual end /
  # state. Encoding and separator follow Redmine's own CSV export (Redmine::Export::CSV).
  class MatrixCsv
    include Redmine::I18n

    # blocks - [[tracker, steps, [[issue, level], ...]], ...]; stages_by_issue - { issue id => [IssueStage] };
    # summaries - { issue id => ProgressSummary }; parents - { issue id => branched_from_issue_id }
    # encoding - 'UTF-8' for the second link (the language's own encoding may not hold every character, e.g.
    #            Japanese with an English user), else nil: the language's encoding, as Redmine's CSV does
    def initialize(blocks, stages_by_issue:, summaries:, parents:, today:, encoding: nil)
      @blocks = blocks
      @stages_by_issue = stages_by_issue
      @summaries = summaries
      @parents = parents
      @today = today
      @encoding = encoding
    end

    def generate
      Redmine::Export::CSV.generate(encoding: @encoding) do |csv|
        @blocks.each_with_index do |(tracker, steps, rows), i|
          csv << [] if i.positive?
          csv << [l('sequential_tasks.table.group_tracker', name: tracker.name)]
          csv << header(steps)
          rows.each { |issue, _level| csv << row(issue, steps) }
        end
      end
    end

    private

    def header(steps)
      columns = ['#', l('sequential_tasks.csv.parent'), l(:field_subject), l(:field_status), l(:field_assigned_to),
                 l(:field_fixed_version), l('sequential_tasks.table.state'), l('sequential_tasks.csv.delay_days'),
                 l(:field_start_date), l(:field_due_date)]
      steps.each do |step|
        name = step.status&.name
        %w[planned_start planned_end actual_start actual_end state].each do |key|
          columns << l("sequential_tasks.csv.stage_#{key}", stage: name)
        end
      end
      columns
    end

    def row(issue, steps)
      summary = @summaries[issue.id]
      by_status = (@stages_by_issue[issue.id] || []).index_by(&:status_id)
      cells = [issue.id, @parents[issue.id], issue.subject, issue.status&.name,
               issue.assigned_to && NameFormat.name(issue.assigned_to), issue.fixed_version&.name,
               state_text(summary), (summary.delay_days if summary&.delayed?),
               format_date(issue.start_date), format_date(issue.due_date)]
      steps.each do |step|
        stage = by_status[step.status_id]
        if stage
          not_started = summary&.not_started_stage?(stage) # as on the screen
          cells.push(format_date(stage.planned_start_date), format_date(stage.planned_end_date),
                     (format_date(UserTime.date_of(stage.actual_start_at)) unless not_started),
                     format_date(UserTime.date_of(stage.actual_end_at)),
                     not_started ? l('sequential_tasks.state.planned') : stage_state_text(stage))
        else
          cells.push(nil, nil, nil, nil, nil)
        end
      end
      cells.map { |c| c == '' ? nil : safe_cell(c) } # nil = an empty cell (not "")
    end

    # A text starting with = + - @ (or a tab or CR) would be taken as a formula by a spreadsheet: a subject filed through
    # the API comes from outside. A leading ' keeps it text (review 2026-11-14)
    def safe_cell(value)
      value.is_a?(String) && value.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value
    end

    # The words of the state column of the screen, without its marks (they do not survive Shift_JIS); the days of
    # a delay are in their own column
    def state_text(summary)
      return nil unless summary

      key = if summary.closed? then 'closed'
            elsif summary.delayed? then 'delayed'
            elsif summary.pending? then 'pending'
            elsif summary.ahead? then 'ahead'
            else 'in_progress'
            end
      l("sequential_tasks.csv.state_#{key}")
    end

    # The badge of a matrix cell, in words (the same rules as _matrix_view)
    def stage_state_text(stage)
      p_end = stage.planned_end_date
      case stage.stage_status
      when 'skipped' then l('sequential_tasks.state.skipped')
      when 'completed'
        a_end = UserTime.date_of(stage.actual_end_at)
        diff = a_end && p_end ? (a_end - p_end).to_i : 0
        l('sequential_tasks.csv.stage_done', diff: diff.positive? ? "+#{diff}" : diff.to_s)
      when 'in_progress'
        late = p_end && @today > p_end ? (@today - p_end).to_i : 0
        late.positive? ? l('sequential_tasks.csv.stage_late', days: late) : l('sequential_tasks.csv.state_in_progress')
      else l('sequential_tasks.state.planned')
      end
    end
  end
end
