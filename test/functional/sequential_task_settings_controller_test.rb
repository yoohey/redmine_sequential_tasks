# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Tracker settings screen (admin). Redmine fixtures: user 1 is the admin; statuses 1 New, 2 Assigned, 3 Resolved.
class SequentialTaskSettingsControllerTest < Redmine::ControllerTest
  tests SequentialTaskSettingsController

  def setup
    @setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index do |status_id, i|
      @setting.steps.create!(status_id: status_id, position: i + 1, default_duration_days: 2)
    end
    @request.session[:user_id] = 1
  end

  def steps
    @setting.steps.reload.map { |s| [s.status_id, s.position, s.default_duration_days] }
  end

  # The pages work under a strict Content Security Policy: no inline styles, scripts or event attributes
  def test_the_settings_pages_have_no_inline_styles_scripts_or_handlers
    [[:index, {}], [:edit, { id: 1 }]].each do |action, params|
      get action, params: params
      assert_response :success
      content = css_select('.sq-settings').to_s # the plugin's part (Redmine's own layout has inline styles)
      assert content.present?, "#{action}: the page"
      assert_no_match(/\sstyle="/, content, "#{action}: inline style")
      assert_no_match(/<script(?![^>]*\ssrc=)/, content, "#{action}: inline script")
      assert_no_match(/\son(change|click|submit)=/, content, "#{action}: event attribute")
    end
  end

  def test_the_color_samples_are_named_by_number_and_color
    get :edit, params: { id: 1 }
    assert_select '.sq-swatch[aria-label*="#"][aria-pressed]', minimum: 1
  end

  def test_a_status_outside_the_workflow_explains_itself
    get :edit, params: { id: 1 }
    assert_select '.sq-not-in-workflow[title]', minimum: 0 # present only for statuses outside the workflow
    assert_select '.sq-not-in-workflow:not([title])', 0
  end

  def test_saving_stages_without_enabling_tells_that_it_is_not_enabled_yet
    put :update, params: { id: 1, steps: [{ status_id: 1, default_duration_days: 2 }] } # no "enabled"
    assert_redirected_to '/sequential_task_settings'
    assert flash[:warning].present?
  end

  def test_only_the_first_stage_may_be_zero_days
    put :update, params: { id: 1, enabled: '1', steps: [
      { status_id: 1, default_duration_days: 0 }, { status_id: 2, default_duration_days: 0 }
    ] }
    assert_equal [[1, 1, 0], [2, 2, 1]], steps, 'the first stage waits to be picked up; the others keep at least one day'
  end

  def test_saving_replaces_the_steps_in_the_given_order
    put :update, params: { id: 1, enabled: '1', steps: [
      { status_id: 3, default_duration_days: 4, color: '#112233' },
      { status_id: 1, default_duration_days: 1, color: '#445566' }
    ] }
    assert_redirected_to '/sequential_task_settings'
    assert_equal [[3, 1, 4], [1, 2, 1]], steps
  end

  def test_the_same_status_twice_is_refused_and_nothing_changes
    before = steps
    put :update, params: { id: 1, enabled: '1', steps: [
      { status_id: 2, default_duration_days: 3 },
      { status_id: 2, default_duration_days: 5 }
    ] }
    assert_response :success # the edit screen is shown again, with the error
    assert flash[:error].present?
    assert_equal before, steps
  end

  def test_the_edit_screen_lists_the_workflow_statuses_with_the_stages_checked
    get :edit, params: { id: 1 }
    assert_response :success
    ids = Tracker.find(1).issue_statuses.map(&:id)
    assert_select 'tbody#steps-tbody tr.step-row', ids.size
    assert_select 'tbody#steps-tbody input.sq-use[checked]', 3
    assert_select 'tbody#steps-tbody tr.step-row.sq-off input[disabled]' # the unchecked rows are switched off
    assert_select 'tbody#steps-tbody tr.step-row:first-child button.sq-swatch', SequentialTaskStep::PALETTE.size
    assert_select 'tbody#steps-tbody tr.step-row:first-child input[type=color][name=?]', 'steps[][color]'
    assert_select 'a', text: /add_stage|工程（ステージ）を追加/, count: 0
  end

  def test_a_stage_whose_status_is_not_in_the_workflow_is_still_listed_with_a_note
    status = IssueStatus.create!(name: 'Outside the workflow') # no workflow mentions it
    @setting.steps.create!(status_id: status.id, position: 4, default_duration_days: 1)
    get :edit, params: { id: 1 }
    assert_select "tbody#steps-tbody input.sq-use[value='#{status.id}'][checked]", 1
    assert_select 'tbody#steps-tbody em', text: I18n.t('sequential_tasks.settings.not_in_workflow')
  end

  def test_the_stored_stage_order_is_kept_on_the_screen
    # the stages are listed first, in their stored order, even when the Redmine order of the statuses differs
    @setting.steps.destroy_all
    [3, 1, 2].each_with_index { |sid, i| @setting.steps.create!(status_id: sid, position: i + 1, default_duration_days: 1) }
    get :edit, params: { id: 1 }
    values = css_select('tbody#steps-tbody input.sq-use[checked]').map { |e| e['value'].to_i }
    assert_equal [3, 1, 2], values
  end

  def test_the_edit_screen_has_the_preview_of_the_stage_flow
    get :edit, params: { id: 1 }
    assert_select '#sq-preview[data-days][data-empty]', 1
    assert_select '#sq-preview-style button', 3 # the three looks to choose from
  end

  def test_the_list_checkbox_switches_a_tracker_off_and_on
    patch :enabled, params: { id: 1, enabled: '0' }
    assert_redirected_to '/sequential_task_settings'
    assert_not @setting.reload.enabled?
    patch :enabled, params: { id: 1, enabled: '1' }
    assert @setting.reload.enabled?
  end

  def test_a_tracker_without_stages_cannot_be_switched_on
    patch :enabled, params: { id: 2, enabled: '1' }
    assert flash[:error].present?
    assert_nil SequentialTaskSetting.find_by(tracker_id: 2)&.enabled?.presence
  end

  def test_the_list_shows_a_checkbox_per_tracker
    get :index
    assert_response :success
    assert_select 'input[type=checkbox][name=enabled]', Tracker.count
  end

  def test_the_bar_style_is_saved_per_tracker_with_the_form
    assert_equal 'bold', @setting.bar_style
    put :update, params: { id: 1, enabled: '1', bar_style: 'subtle', steps: [{ status_id: 1, default_duration_days: 1 }] }
    assert_equal 'subtle', @setting.reload.bar_style
    other = SequentialTaskSetting.create!(tracker_id: 2, enabled: true)
    assert_equal 'bold', other.reload.bar_style, 'another tracker keeps its own look'
    get :edit, params: { id: 1 }
    assert_select 'input#bar_style[value=subtle]'
  end

  def test_an_unknown_bar_style_becomes_the_default
    @setting.update!(bar_style: 'light')
    put :update, params: { id: 1, enabled: '1', bar_style: 'neon', steps: [{ status_id: 1, default_duration_days: 1 }] }
    assert_equal 'bold', @setting.reload.bar_style
  end

  def test_a_failed_save_does_not_change_the_bar_style
    put :update, params: { id: 1, enabled: '1', bar_style: 'light', steps: [{ status_id: 2, default_duration_days: 3 }, { status_id: 2, default_duration_days: 5 }] }
    assert_equal 'bold', @setting.reload.bar_style
  end

  def test_the_sample_colors_are_distinct_and_keep_away_from_the_delay_red
    palette = SequentialTaskStep::PALETTE
    assert_equal palette.size, palette.uniq.size
    assert_not_includes palette, '#ef4444'
  end
end
