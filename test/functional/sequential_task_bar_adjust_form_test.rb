# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The stage timeline on the issue page and its "adjust the schedule" controls.
# What the server renders is checked here; the widths themselves are set by the page's script
# (base + 10px per extra day) and were checked in a browser.
# Redmine fixtures: user 2 (jsmith) is a Manager of project 1; statuses 1 New, 2 Assigned, 3 Resolved.
class SequentialTaskBarAdjustFormTest < Redmine::ControllerTest
  tests IssuesController

  def setup
    Setting.non_working_week_days = %w[6 7]
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    @request.session[:user_id] = 2
    Project.find(1).enable_module!(:sequential_tasks)
  end

  def steps(*days)
    days.each_with_index { |d, i| @setting.steps.create!(status_id: [1, 2, 3][i], position: i + 1, default_duration_days: d) }
  end

  def test_the_mode_switch_sits_in_the_heading_row_and_joins_the_form
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    get :show, params: { id: issue.id }

    # outside the form (in the heading row), its radios belong to it through the form attribute
    assert_select '#sequential-task-stage-edit-form #stage-mode-switch', 0
    assert_select "#stage-mode-switch input[name=mode][value=fixed_due][checked][form='sequential-task-stage-edit-form']"
    assert_select "#stage-mode-switch input[name=mode][value=push][form='sequential-task-stage-edit-form']"
    assert_select '#stage-mode-switch label[title]', 2 # the explanation of each mode
  end

  def test_every_adjustable_stage_has_a_box_a_handle_and_an_editable_day_count
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    stages = issue.issue_stages.order(:position).to_a
    get :show, params: { id: issue.id }

    assert_select '#stage-pipeline-bar .stage-drag-seg', 3
    # the last stage (the slack) is not grayed out; its handle (the due date edge) is hidden in fixed_due mode
    assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{stages.last.id}'] input.stage-duration-input"
    assert_select '#stage-pipeline-bar input.stage-duration-input[disabled]', 0
    assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{stages.last.id}'] .stage-drag-handle-slack[style*='visibility: hidden']"
    assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{stages.first.id}'] .stage-drag-handle"
    # only the "does not fit" warning is left; no "adjusted automatically" note
    assert_select '.stage-slack-note', 1
  end

  def test_the_callouts_at_the_start_the_boundaries_and_the_due_date
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    first = issue.issue_stages.order(:position).first
    get :show, params: { id: issue.id }

    assert_select '#stage-pipeline-bar #stage-start-pill .stage-start-date', text: RedmineSequentialTasks::DateFormat.short(first.planned_start_date)
    assert_select "#stage-plan-pill-#{first.id} .stage-plan-date"
    assert_select '#stage-pipeline-bar #stage-due-pill .stage-due-date'
  end

  def test_the_boxes_carry_the_days_and_the_look_of_the_project_timeline
    steps(3, 6, 9)
    # Started yesterday, every day a working day: the first stage is the current one on any day of the week (filed on
    # a weekend with the default start date, it would start on Monday: not started yet)
    Setting.non_working_week_days = []
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, start_date: Date.today - 1)
    stages = issue.issue_stages.order(:position).to_a
    get :show, params: { id: issue.id }

    # the state classes and the stage color of the project's timeline, and the tracker's bar style
    assert_select "#sq-stage-timeline #stage-pipeline-bar.sq-style-#{RedmineSequentialTasks::BarStyle.normalize(@setting.reload.bar_style)}"
    assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{stages.first.id}'].sq-bar-cur[style*='--c:']"
    assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{stages.last.id}'].sq-bar-future"
    # the script sizes each box from its days
    [3, 6, 9].zip(stages).each do |days, stage|
      assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{stage.id}'][data-orig-duration='#{days}']"
    end
  end

  def test_a_zero_day_stage_gets_no_box
    steps(0, 3, 3) # the first stage is a wait
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    wait = issue.issue_stages.order(:position).first
    assert wait.zero_day
    get :show, params: { id: issue.id }

    assert_select '#stage-pipeline-bar .stage-drag-seg', 2
    assert_select "#stage-pipeline-bar .stage-drag-seg[data-stage-id='#{wait.id}']", 0
  end

  def test_the_start_date_can_be_typed_while_no_stage_has_finished
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    get :show, params: { id: issue.id }

    assert_select 'label.sq-start-bubble:not(.sq-start-locked) input#stage-start-input[name=start_date]:not([disabled])'
  end

  def test_the_start_date_is_grayed_out_with_the_reason_once_a_stage_has_finished
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    issue.reload
    issue.status_id = 2 # the first stage finishes
    issue.save!
    get :show, params: { id: issue.id }

    assert_select 'label.sq-start-bubble.sq-start-locked[title] input#stage-start-input[disabled]'
  end

  def test_no_mode_switch_with_only_one_adjustable_stage
    steps(3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 2) # the last stage is the current (only adjustable) one
    get :show, params: { id: issue.id }
    assert_select '#stage-mode-switch', 0
  end

  # each adjustable stage has its own "count the non-working days too" box while adjusting
  def test_each_adjustable_stage_has_a_box_to_count_the_non_working_days
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    stages = issue.issue_stages.order(:position).to_a
    stages[1].update!(count_non_working: true)
    get :show, params: { id: issue.id }

    assert_select '#stage-pipeline-bar input.stage-all-days[type=checkbox]', 3
    assert_select "input[type=hidden][name='stages[#{stages[1].id}][count_non_working]'][value='0']"
    assert_select "input.stage-all-days[name='stages[#{stages[1].id}][count_non_working]'][checked]"
    assert_select ".stage-drag-seg[data-stage-id='#{stages[1].id}'][data-all-days='1']"
  end

  # no working day within half a year: no adjusting, and the reason is shown
  def test_without_any_working_day_there_is_no_adjusting
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    get :show, params: { id: issue.id }

    assert_response :success
    assert_select '.sq-no-working-day'
    assert_select '#stage-edit-controls', 0
    assert_select '#sq-stage-timeline [data-sq-act="adjust"]', 0
  end

  # Review 2026-11-14: the behavior is in assets (sequential_dates.js, sequential_task_bar.js), not in the page:
  # no inline script and no event attributes (works with a strict Content-Security-Policy too)
  def test_the_stage_timeline_has_no_inline_script_or_event_attributes
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    get :show, params: { id: issue.id }

    assert_select '#sq-stage-timeline script:not([src])', 0
    assert_select '#sq-stage-timeline style', 0
    assert_select '#sq-stage-timeline [onclick], #sq-stage-timeline [onchange], #sq-stage-timeline [oninput], #sq-stage-timeline [onfocus], #sq-stage-timeline [onsubmit]', 0
    assert_select '#sq-stage-timeline script[src*="sequential_task_bar"]'
    assert_select '#sq-stage-timeline[data-non-working]'
    assert_select '#stage-save-button'
  end

  # Review 2026-11-14: the bar is not shown where the module is off (its buttons would answer 403)
  def test_no_bar_where_the_module_is_off
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    Project.find(1).disable_module!(:sequential_tasks)
    get :show, params: { id: issue.id }
    assert_select '#sq-stage-timeline', 0
  end

  # Touch, keyboard and screen readers (2026-11-14)
  def test_the_controls_have_names_and_the_mode_and_reasons_are_on_screen
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    get :show, params: { id: issue.id }
    assert_select '.stage-duration-input[aria-label]', 3
    assert_select '.stage-all-days[aria-label]', 3
    assert_select '#stage-mode-hint[aria-live]'
    assert_select '#stage-mode-switch label[data-hint]', 2
    assert_select '#sq-stage-timeline[data-t-discard]'
  end

  def test_a_grayed_out_start_date_shows_its_reason_on_screen
    steps(3, 3, 3)
    issue = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1)
    issue.reload
    issue.status_id = 2
    issue.save!
    get :show, params: { id: issue.id }
    assert_select 'label.sq-start-locked #stage-start-why'
    assert_select '#stage-start-input[aria-describedby="stage-start-why"]'
  end
end
