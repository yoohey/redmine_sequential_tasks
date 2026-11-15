# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# sort kinds, the order of siblings on the screens, and the reorder mode switch.
class SequentialTasksOrderScreenTest < Redmine::ControllerTest
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

  def test_the_default_order_is_by_position_then_id
    SequentialTaskIssue.create!(issue_id: @c.id, position: 1)
    SequentialTaskIssue.create!(issue_id: @a.id, position: 2)
    index
    assert_equal [@c.id, @a.id, @b.id], shown_ids & ours
  end

  def test_the_due_date_order
    index(sort: 'due')
    assert_equal [@b.id, @c.id, @a.id], shown_ids & ours
  end

  def test_an_unknown_sort_is_the_manual_order
    index(sort: 'bogus')
    assert_equal ours, shown_ids & ours
  end

  def test_branches_stay_under_their_parent_in_every_sort
    kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'kid of A', due_date: Date.today + 1)
    SequentialTaskIssue.create!(issue_id: kid.id, branched_from_issue_id: @a.id, position: 1)
    %w[manual due delay updated].each do |kind|
      index(sort: kind)
      ids = shown_ids
      assert_equal ids.index(@a.id) + 1, ids.index(kid.id), "sort=#{kind}: the branch follows its parent"
    end
  end

  def test_branches_are_ordered_among_their_siblings
    k1 = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'k1')
    k2 = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'k2')
    SequentialTaskIssue.create!(issue_id: k1.id, branched_from_issue_id: @a.id, position: 2)
    SequentialTaskIssue.create!(issue_id: k2.id, branched_from_issue_id: @a.id, position: 1)
    index(view: 'matrix')
    assert_equal [k2.id, k1.id], shown_ids & [k1.id, k2.id]
  end

  def test_the_sort_is_kept_in_the_links_of_the_toolbar
    index(sort: 'due', zoom: 'weeks')
    assert_select 'select[data-sort] option[selected][value*="sort=due"]'
    assert_select 'input[data-switch=show-closed][data-href*="sort=due"]'
  end

  # --- reorder mode

  def test_users_who_may_edit_issues_get_the_switch_and_the_handles_in_the_manual_order
    index
    assert_select 'th.sq-th-issue button.sq-mode-btn[aria-pressed=false]'
    assert_select '#sq-root[data-reorder-url]'
    assert_equal shown_ids.size, css_select('tr.issue-row .sq-hd').size, 'every row has its handle'
    assert_select 'tr.issue-row[data-id]'
  end

  def test_the_matrix_has_the_switch_and_handles_too
    index(view: 'matrix')
    assert_select 'th.sq-th-issue button.sq-mode-btn'
    assert_equal shown_ids.size, css_select('tr.issue-row .sq-hd').size
  end

  def test_the_switch_and_handles_are_hidden_in_the_automatic_sorts
    %w[due delay updated].each do |kind|
      index(sort: kind)
      assert_equal 0, css_select('.sq-mode-btn').size, "sort=#{kind}"
      assert_equal 0, css_select('.sq-hd').size, "sort=#{kind}"
    end
  end

  def test_users_who_may_not_edit_issues_do_not_get_the_switch
    @request.session[:user_id] = nil
    index
    assert_equal 0, css_select('.sq-mode-btn').size
    assert_equal 0, css_select('.sq-hd').size
    assert_equal 0, css_select('#sq-root[data-reorder-url]').size
  end

  def test_the_mode_is_never_remembered_by_the_server
    index(reorder: '1')
    assert_select 'th.sq-th-issue button.sq-mode-btn[aria-pressed=false]'
    assert_select '#sq-root.sq-reorder', 0
  end

  def test_a_row_with_the_handles_is_still_small
    index(show_closed: '1')
    assert css_select('tr.issue-row').map { |r| r.to_s.bytesize }.max < 3500
  end

  # --- folding branches (the button itself is added by JavaScript)

  def test_rows_tell_their_parent_so_that_branches_can_be_folded_for_everyone
    kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'kid')
    SequentialTaskIssue.create!(issue_id: kid.id, branched_from_issue_id: @a.id, position: 1)
    @request.session[:user_id] = nil
    index
    assert_select "tr.issue-row[data-id='#{kid.id}'][data-p='#{@a.id}']"
    assert_select "tr.issue-row[data-id='#{@a.id}'][data-p='']"
    assert_select '#sq-root[data-t-fold]'
  end

  # --- a branch whose parent is not in the list

  def test_a_branch_whose_parent_is_not_listed_shows_a_parent_number_chip_with_the_parents_name
    kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'kid')
    SequentialTaskIssue.create!(issue_id: kid.id, branched_from_issue_id: @a.id, position: 1)
    @a.update!(status_id: 5) # finished: not in the initial list
    index
    assert_select "a.sq-orphan[href='/issues/#{@a.id}']", text: "🌿 ↰ ##{@a.id}"
    assert_includes css_select('a.sq-orphan').first['title'], @a.subject
    assert_equal 0, css_select("tr[data-id='#{kid.id}'] .sq-tree").size
  end

  def test_a_branch_under_its_listed_parent_has_the_tree_mark_and_no_chip
    kid = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'kid')
    SequentialTaskIssue.create!(issue_id: kid.id, branched_from_issue_id: @a.id, position: 1)
    index
    assert_select "tr[data-id='#{kid.id}'] .sq-tree"
    assert_select "tr[data-id='#{kid.id}'] a.sq-orphan", 0
  end

  def test_the_slow_stage_chips_can_be_switched_off_in_the_toolbar
    index
    assert_select 'input[data-act=slow][checked]', 1
    assert_includes File.read(File.expand_path('../../assets/stylesheets/sequential_tasks.css', __dir__)), '.sq-slow-off .sq-sl'
  end

  def test_each_row_carries_the_bar_style_of_its_tracker
    index
    assert_select 'tr.issue-row.sq-style-bold'
    SequentialTaskSetting.find_by(tracker_id: 1).update!(bar_style: 'subtle')
    index
    assert_select 'tr.issue-row.sq-style-subtle'
    assert_select 'tr.issue-row.sq-style-bold', 0
  end

  def test_the_red_subjects_follow_the_lightning_line_in_the_timeline
    index
    assert_select '#sq-root.sq-lightning-on'
    index(view: 'matrix')
    assert_select '#sq-root.sq-lightning-on', 0
  end

  def test_the_two_show_switches_stay_together_on_one_line
    index
    assert_select '.sq-nowrap input[data-switch=show-closed]'
    assert_select '.sq-nowrap input[data-switch=show-pending]'
  end

  # --- what comes from data is escaped in the cells of a row (SequentialTasksHelper)

  def test_the_cells_of_a_row_escape_subject_and_names
    @a.update!(subject: '<script>alert(1)</script> & "quoted"', assigned_to_id: 2)
    User.find(2).update!(firstname: '<b>Bold</b>')
    %w[timeline matrix].each do |view|
      index(view: view)
      assert_not_includes response.body, '<script>alert(1)</script>'
      assert_not_includes response.body, '<b>Bold</b>'
      assert_includes response.body, '&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quoted&quot;'
    end
  end

  def test_the_timeline_and_the_matrix_build_their_issue_and_state_cells_the_same_way
    index
    timeline_cell = css_select("tr[data-id='#{@a.id}'] td.sq-c-issue .sq-ib > *").map { |n| n['class'] }
    index(view: 'matrix')
    matrix_cell = css_select("tr[data-id='#{@a.id}'] td.sq-c-issue .sq-ib > *").map { |n| n['class'] }
    assert_equal timeline_cell, matrix_cell
    assert_select "tr[data-id='#{@a.id}'] td.sq-c-state .sq-sb"
  end
end
