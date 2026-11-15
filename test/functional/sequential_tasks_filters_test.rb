# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Filters of the toolbar and the groups they share: version, category, current stage
# and state. Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTasksFiltersTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index { |s, i| setting.steps.create!(status_id: s, position: i + 1, default_duration_days: 3) }
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')
    SequentialTaskIssue.delete_all

    @a = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'A', due_date: Date.today + 9)
    @b = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'B', due_date: Date.today + 3)
    @c = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'C', due_date: Date.today + 6)
    @request.session[:user_id] = 2
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  def shown_ids
    css_select('tr.issue-row a.sq-subj').map { |a| a['href'][%r{/issues/(\d+)}, 1].to_i }
  end

  def ours
    [@a, @b, @c].map(&:id)
  end

  # --- version (roadmap) filter and grouping

  def versioned
    @v1 = Version.create!(project_id: 1, name: 'Roadmap-A', effective_date: Date.today + 30)
    @v2 = Version.create!(project_id: 1, name: 'Roadmap-B', effective_date: Date.today + 10)
    @a.update!(fixed_version_id: @v1.id)
    @b.update!(fixed_version_id: @v2.id)
  end

  def test_filtering_by_version
    versioned
    index(version_id: @v1.id)
    assert_equal [@a.id], shown_ids & ours
    assert_select 'select[data-version] option[selected]', text: /Roadmap-A/
  end

  def test_filtering_by_no_version
    versioned
    index(version_id: 'none')
    assert_equal [@c.id], shown_ids & ours
  end

  def test_an_unknown_version_is_ignored
    versioned
    index(version_id: '999999')
    assert_equal ours.sort, (shown_ids & ours).sort
  end

  def test_the_version_filter_is_kept_in_the_other_links
    versioned
    index(version_id: @v1.id)
    assert_select "input[data-switch=show-closed][data-href*='version_id=#{@v1.id}']"
  end

  def test_grouping_by_version_orders_groups_by_date_and_puts_no_version_last
    versioned
    index(group_by: 'version')
    titles = css_select('tr.group-header-row th.sq-gh').map { |t| t.text.squish }
    assert_match(/Roadmap-B/, titles[0])
    assert_match(/Roadmap-A/, titles[1])
    assert_match(/#{Regexp.escape(I18n.t('sequential_tasks.table.group_version_none', locale: User.find(2).language.presence || 'en'))}/, titles.last)
  end

  def test_the_toolbar_has_links_for_all_branches
    index
    assert_select '#sq-branch-folds a[data-act=branches-expand]'
    assert_select '#sq-branch-folds a[data-act=branches-collapse]'
  end

  # --- category, stage and state filters

  def categorized
    @cat1 = IssueCategory.create!(project_id: 1, name: 'Cat-Front')
    @cat2 = IssueCategory.create!(project_id: 1, name: 'Cat-Back')
    @a.update!(category_id: @cat1.id)
    @b.update!(category_id: @cat2.id)
  end

  def test_filtering_by_category
    categorized
    index(category_id: @cat1.id)
    assert_equal [@a.id], shown_ids & ours
    assert_select 'select[data-category] option[selected]', text: /Cat-Front/
  end

  def test_filtering_by_no_category
    categorized
    index(category_id: 'none')
    assert_equal [@c.id], shown_ids & ours
  end

  def test_grouping_by_category_puts_issues_without_a_category_last
    categorized
    index(group_by: 'category')
    titles = css_select('tr.group-header-row th.sq-gh').map { |t| t.text.squish }
    assert_match(/Cat-Back/, titles[0])
    assert_match(/Cat-Front/, titles[1])
    assert_match(/#{Regexp.escape(I18n.t('sequential_tasks.table.group_category_none', locale: User.find(2).language.presence || 'en'))}/, titles.last)
  end

  def test_filtering_by_current_stage
    @b.update!(status_id: 2) # the second stage; the others are at the first
    index(stage: 2)
    assert_includes shown_ids, @b.id
    assert_not_includes shown_ids, @a.id
    assert_select 'select[data-stage] option[selected]'
  end

  def test_an_unknown_stage_is_ignored
    index(stage: 999)
    assert_equal ours.sort, (shown_ids & ours).sort
  end

  def test_filtering_by_state_shows_only_issues_in_that_state
    # @a is not delayed (it just started); a delayed issue: its first stage ended long ago
    late = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'late', start_date: Date.today - 40)
    late.issue_stages.update_all(planned_start_date: Date.today - 40, planned_end_date: Date.today - 30)
    index(state: 'delayed')
    assert_includes shown_ids, late.id
    assert_not_includes shown_ids, @a.id
    index(state: 'in_progress')
    assert_not_includes shown_ids, late.id
  end

  def test_an_unknown_state_is_ignored
    index(state: 'bogus')
    assert_equal ours.sort, (shown_ids & ours).sort
  end

  def test_the_new_filters_are_kept_in_the_links
    categorized
    index(category_id: @cat1.id, state: 'delayed', stage: 1)
    assert_select "input[data-switch=show-closed][data-href*='category_id=#{@cat1.id}']"
    assert_select "input[data-switch=show-closed][data-href*='state=delayed']"
    assert_select "input[data-switch=show-closed][data-href*='stage=1']"
  end
end
