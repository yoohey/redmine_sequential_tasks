# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The screens, flash messages and issue history in Japanese and English.
# Redmine fixtures: user 1 admin, user 2 (jsmith) Manager of project 1; statuses 1 New, 2 Assigned, 3 Resolved,
# 4 Feedback (no stage), 5 Closed.
module SequentialTasksI18nSetup
  CJK = /[　-〿぀-ヿ一-鿿＀-￯]/

  def setup_sequential_tasks_data
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index do |status_id, i|
      setting.steps.create!(status_id: status_id, position: i + 1, default_duration_days: 3)
    end
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')

    @active = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'active issue')
    @late = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'late issue',
                            start_date: Date.today - 60)
    @pending = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'not started issue',
                               start_date: Date.today + 28)
    @closed = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'finished issue')
    @closed.update!(status_id: 5)
    @skipped = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'skipping issue')
    @skipped.update!(status_id: 3)
    @waiting = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'waiting issue')
    @waiting.update!(status_id: 2)
    @waiting.reload.update!(status_id: 4)
    @child = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'branched issue')
    SequentialTaskIssue.create!(issue_id: @child.id, branched_from_issue_id: @active.id, position: 1)
  end

  def use_language(user_id, language)
    User.find(user_id).update_column(:language, language)
    @request.session[:user_id] = user_id
  end

  def assert_english(body)
    assert_no_match CJK, body, 'Japanese text on an English screen'
    assert_no_match(/translation missing/i, body)
  end
end

class SequentialTasksI18nTest < Redmine::ControllerTest
  include SequentialTasksI18nSetup
  tests SequentialTasksController

  def setup
    setup_sequential_tasks_data
  end

  %w[timeline matrix].each do |view|
    define_method("test_#{view}_in_english_has_no_japanese") do
      use_language(2, 'en')
      get :index, params: { project_id: 'ecookbook', view: view, show_closed: '1', show_pending: '1' }
      assert_response :success
      assert_english response.body
      assert_includes response.body, 'Show finished'
    end

    define_method("test_#{view}_in_japanese") do
      use_language(2, 'ja')
      get :index, params: { project_id: 'ecookbook', view: view, show_closed: '1', show_pending: '1' }
      assert_response :success
      assert_includes response.body, '完了も表示'
      assert_no_match(/translation missing/i, response.body)
    end
  end

  def test_the_timeline_in_english_covers_every_group_by
    use_language(2, 'en')
    %w[tracker assigned_to status].each do |group_by|
      get :index, params: { project_id: 'ecookbook', group_by: group_by, show_closed: '1' }
      assert_english response.body
    end
  end

  def test_other_languages_fall_back_to_english
    use_language(2, 'fr')
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_no_match(/translation missing/i, response.body)
    assert_includes response.body, 'Show finished'
  end
end

class SequentialTaskIssueBarI18nTest < Redmine::ControllerTest
  include SequentialTasksI18nSetup
  tests IssuesController

  def setup
    setup_sequential_tasks_data
  end

  def test_the_issue_screen_in_english_has_no_japanese
    use_language(2, 'en')
    [@active, @late, @closed, @skipped, @waiting, @child].each do |issue|
      get :show, params: { id: issue.id }
      assert_response :success
      assert_english response.body
      assert_select '#sq-stage-timeline .sqb-title', /Timeline/
    end
  end

  def test_the_issue_screen_in_japanese
    use_language(2, 'ja')
    get :show, params: { id: @waiting.id }
    assert_select '#sq-stage-timeline .sqb-title', /タイムライン/
    assert_includes response.body, 'ステージにありません'
    get :show, params: { id: @child.id }
    assert_includes response.body, '派生元'
  end
end

class SequentialTaskStagesI18nTest < Redmine::ControllerTest
  include SequentialTasksI18nSetup
  tests SequentialTaskStagesController

  def setup
    setup_sequential_tasks_data
  end

  def adjust(issue)
    current = issue.issue_stages.reload.find { |s| s.stage_status == 'in_progress' }
    put :update, params: { issue_id: issue.id, stages: { current.id.to_s => { duration_days: 9 } } }
  end

  def test_flash_and_history_in_english
    use_language(2, 'en')
    adjust(@active)
    assert_equal I18n.t('sequential_tasks.flash.schedule_updated', locale: :en), flash[:notice]
    notes = @active.journals.reorder(:id).last.notes
    assert_no_match CJK, notes
    assert_includes notes, 'working days'
  end

  def test_flash_and_history_in_japanese
    use_language(2, 'ja')
    adjust(@active)
    assert_equal I18n.t('sequential_tasks.flash.schedule_updated', locale: :ja), flash[:notice]
    assert_includes @active.journals.reorder(:id).last.notes, '営業日'
  end

  def test_the_error_message_for_a_closed_issue_follows_the_language
    use_language(2, 'en')
    put :update, params: { issue_id: @closed.id, stages: {} }
    assert_equal I18n.t('sequential_tasks.flash.nothing_adjustable', locale: :en), flash[:error]
  end
end

class SequentialTaskBranchesI18nTest < Redmine::ControllerTest
  include SequentialTasksI18nSetup
  tests SequentialTaskBranchesController

  def setup
    setup_sequential_tasks_data
  end

  def test_the_created_message_in_english
    use_language(2, 'en')
    post :create, params: { issue_id: @active.id, subject: 'a branch' }
    assert_match(/was created/, flash[:notice])
    assert_no_match CJK, flash[:notice]
  end

  def test_the_failure_message_in_english
    use_language(2, 'en')
    post :create, params: { issue_id: @active.id, subject: 'a branch', assigned_to_id: 1 }
    assert_match(/Failed to create/, flash[:error])
    assert_no_match CJK, flash[:error]
  end
end

class SequentialTaskSettingsI18nTest < Redmine::ControllerTest
  include SequentialTasksI18nSetup
  tests SequentialTaskSettingsController

  def setup
    setup_sequential_tasks_data
  end

  def test_the_settings_screens_in_english_have_no_japanese
    use_language(1, 'en')
    get :index
    assert_response :success
    assert_english response.body
    get :edit, params: { id: 1 }
    assert_response :success
    assert_english response.body
    assert_includes response.body, 'Standard days'
  end

  def test_the_settings_screens_in_japanese
    use_language(1, 'ja')
    get :edit, params: { id: 1 }
    assert_includes response.body, '標準日数'
  end
end

class SequentialTaskPluginSettingsI18nTest < Redmine::ControllerTest
  include SequentialTasksI18nSetup
  tests SettingsController

  def test_the_plugin_settings_screen_in_english
    use_language(1, 'en')
    get :plugin, params: { id: 'redmine_sequential_tasks' }
    assert_response :success
    assert_english response.body
    assert_includes response.body, 'per-tracker settings'
  end
end
