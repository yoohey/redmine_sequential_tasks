# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The right panel that shows the issue next to the timeline: the page it shows is
# Redmine's own issue page, without the frame around it. Redmine fixtures: user 2 (jsmith) is a Manager of project 1.
class SequentialTasksEmbedTest < Redmine::ControllerTest
  tests IssuesController

  def setup
    @request.session[:user_id] = 2
  end

  def test_an_issue_page_loaded_into_an_iframe_loses_the_frame_around_it
    @request.headers['Sec-Fetch-Dest'] = 'iframe'
    get :show, params: { id: 1 }
    assert_response :success
    assert_select 'style#sq-embed'
    assert_includes css_select('style#sq-embed').first.text, '#main-menu'
    assert_includes css_select('style#sq-embed').first.text, '#sticky-issue-header', "Redmine's sticky issue title would show as a second title band under the panel's own"
    assert_match(/#main \{[^}]*padding: 0/, css_select('style#sq-embed').first.text, "Redmine keeps room for its fixed header above the content")
    assert_select '#content .issue' # the issue itself stays
  end

  def test_the_first_load_asks_for_it_with_a_parameter_for_browsers_without_the_header
    get :show, params: { id: 1, sq_embed: '1' }
    assert_select 'style#sq-embed'
  end

  def test_an_ordinary_page_view_is_left_alone
    get :show, params: { id: 1 }
    assert_select 'style#sq-embed', 0
    @request.headers['Sec-Fetch-Dest'] = 'document'
    get :show, params: { id: 1 }
    assert_select 'style#sq-embed', 0
  end
end

class SequentialTasksPanelTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    setting.steps.create!(status_id: 1, position: 1, default_duration_days: 3)
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    Issue.generate!(project_id: 1, tracker_id: 1, subject: 'a row')
    @request.session[:user_id] = 2
  end

  %w[timeline matrix].each do |view|
    define_method("test_the_#{view}_carries_the_template_of_the_panel") do
      get :index, params: { project_id: 'ecookbook', view: view }
      assert_response :success
      assert_select 'template#sq-panel-template aside#sq-panel[hidden] iframe.sq-panel-frame'
      assert_select 'template#sq-panel-template .sq-panel-open'
      assert_select 'template#sq-panel-template button.sq-panel-close'
    end
  end

  def test_the_subjects_still_link_to_the_issue_pages_for_ctrl_click_and_middle_click
    get :index, params: { project_id: 'ecookbook' }
    assert_select 'a.sq-subj[href^="/issues/"]'
  end
end
