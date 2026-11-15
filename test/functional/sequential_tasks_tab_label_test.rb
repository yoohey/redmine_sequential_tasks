# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The name of the project menu tab: the plugin setting "tab_label", or the name in the locale files when it is blank.
# It is also the heading of the timeline, the matrix and the analysis screens. Redmine fixtures: user 2 (jsmith) is a
# Manager of project 1 (ecookbook).
class SequentialTasksTabLabelTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    @request.session[:user_id] = 2
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def teardown
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def tab
    css_select('#main-menu a.sequential-tasks').first&.text
  end

  def test_blank_means_the_name_in_the_locale_files
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_equal ::I18n.t('sequential_tasks.menu.project'), tab
    assert_select '#content h2', text: ::I18n.t('sequential_tasks.menu.project')
  end

  def test_the_set_name_is_the_tab_and_the_heading
    Setting.plugin_redmine_sequential_tasks = { 'tab_label' => '  Stages  ' }
    get :index, params: { project_id: 'ecookbook', view: 'matrix' }
    assert_equal 'Stages', tab
    assert_select '#content h2', text: 'Stages'
  end

  def test_a_long_name_is_cut_and_markup_is_shown_as_text
    Setting.plugin_redmine_sequential_tasks = { 'tab_label' => '<b>x</b>' + 'y' * 40 }
    get :index, params: { project_id: 'ecookbook' }
    assert_equal ('<b>x</b>' + 'y' * 40)[0, RedmineSequentialTasks::TabLabel::MAX_LENGTH], tab
    assert_select '#main-menu b', 0
  end
end

# The field on the plugin settings screen. Fixture user 1 is the admin.
class SequentialTasksTabLabelSettingTest < Redmine::ControllerTest
  tests SettingsController

  def setup
    @request.session[:user_id] = 1
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def teardown
    Setting.plugin_redmine_sequential_tasks = {}
  end

  def test_the_field_shows_the_default_as_a_hint_and_saves
    get :plugin, params: { id: 'redmine_sequential_tasks' }
    assert_select "input#settings_tab_label[name='settings[tab_label]'][maxlength='30'][placeholder=?]", ::I18n.t('sequential_tasks.menu.project')
    post :plugin, params: { id: 'redmine_sequential_tasks', settings: { tab_label: '工程' } }
    assert_equal '工程', Setting.plugin_redmine_sequential_tasks['tab_label']
  end
end
