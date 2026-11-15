# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The plugin settings screen (Administration > Plugins > Configure). Fixture user 1 is the admin.
class SequentialTasksPluginSettingsTest < Redmine::ControllerTest
  tests SettingsController

  def setup
    @request.session[:user_id] = 1
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def test_the_name_order_can_be_chosen
    get :plugin, params: { id: 'redmine_sequential_tasks' }
    assert_response :success
    assert_select 'select#settings_name_order option', 3
    assert_select 'select#settings_name_order option[value=redmine][selected]'
    assert_select 'select#settings_name_order option[value=first_last]'
    assert_select 'select#settings_name_order option[value=last_first]'
  end

  def test_the_saved_choice_is_selected_again
    Setting.plugin_redmine_sequential_tasks = { 'name_order' => 'last_first' }
    get :plugin, params: { id: 'redmine_sequential_tasks' }
    assert_select 'select#settings_name_order option[value=last_first][selected]'
  end

  def test_saving_the_name_order
    post :plugin, params: { id: 'redmine_sequential_tasks', settings: { name_order: 'last_first' } }
    assert_redirected_to '/settings/plugin/redmine_sequential_tasks'
    assert_equal 'last_first', Setting.plugin_redmine_sequential_tasks['name_order']
  end

  # Candidates on the left, the chosen trackers on the right (the right list is what is saved)
  def test_the_milestone_trackers_are_two_lists_that_together_hold_every_tracker
    get :plugin, params: { id: 'redmine_sequential_tasks' }
    assert_select 'select#available_milestone_trackers[multiple] option', Tracker.count
    assert_select 'select#settings_milestone_tracker_ids[multiple][name="settings[milestone_tracker_ids][]"] option', 0
    assert_select 'button.move-right'
    assert_select 'button.move-left'
  end

  def test_the_saved_milestone_trackers_are_in_the_right_list_and_selected
    Setting.plugin_redmine_sequential_tasks = { 'milestone_tracker_ids' => %w[2 3] }
    get :plugin, params: { id: 'redmine_sequential_tasks' }
    assert_select 'select#settings_milestone_tracker_ids option[value="2"][selected]'
    assert_select 'select#settings_milestone_tracker_ids option[value="3"][selected]'
    assert_select 'select#settings_milestone_tracker_ids option', 2
    assert_select 'select#available_milestone_trackers option[value="1"]'
    assert_select 'select#available_milestone_trackers option[value="2"]', 0
  end

  def test_saving_the_milestone_trackers
    post :plugin, params: { id: 'redmine_sequential_tasks', settings: { name_order: 'redmine', milestone_tracker_ids: ['', '2'] } }
    assert_equal [2], RedmineSequentialTasks::MilestoneSettings.tracker_ids
  end

  def test_no_milestone_trackers_by_default
    assert_equal [], RedmineSequentialTasks::MilestoneSettings.tracker_ids
  end
end
