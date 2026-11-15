# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# Project screen filters (initial view: unfinished issues, switches for finished
# and not-started issues). Redmine fixtures: user 2 (jsmith) is a Manager of project 1 (ecookbook).
class SequentialTasksControllerTest < Redmine::ControllerTest
  tests SequentialTasksController

  def setup
    Setting.non_working_week_days = %w[6 7]
    setting = SequentialTaskSetting.create!(tracker_id: 1, enabled: true)
    [1, 2, 3].each_with_index do |status_id, i|
      setting.steps.create!(status_id: status_id, position: i + 1, default_duration_days: 3)
    end
    EnabledModule.create!(project_id: 1, name: 'sequential_tasks')

    # started a week ago: with "today" as its start, a run on a weekend moved it to Monday, so it was "not started"
    @active = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'active issue', start_date: Date.today - 7)
    @pending = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'not started issue',
                               start_date: Date.today + 28)
    @closed = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'finished issue')
    @closed.update!(status_id: 5)

    @request.session[:user_id] = 2
  end

  def shown?(issue)
    css_select("a[href='/issues/#{issue.id}']").any?
  end

  def index(params = {})
    get :index, params: { project_id: 'ecookbook' }.merge(params)
    assert_response :success
  end

  %w[timeline matrix].each do |view|
    define_method("test_#{view}_initially_shows_unfinished_issues_including_not_started_ones") do
      index(view: view)
      assert shown?(@active)
      assert shown?(@pending)
      assert !shown?(@closed)
    end

    define_method("test_#{view}_shows_finished_issues_on_request") do
      index(view: view, show_closed: '1')
      assert shown?(@closed)
      assert shown?(@active)
    end

    define_method("test_#{view}_hides_not_started_issues_on_request") do
      index(view: view, show_pending: '0')
      assert !shown?(@pending)
      assert shown?(@active)
    end

    define_method("test_#{view}_can_show_everything") do
      index(view: view, show_closed: '1', show_pending: '1')
      assert shown?(@active)
      assert shown?(@pending)
      assert shown?(@closed)
    end
  end

  def test_the_switches_show_how_many_issues_they_cover
    closed_total = Issue.where(project_id: 1, tracker_id: 1).select(&:closed?).size
    index
    assert_includes response.body, I18n.t('sequential_tasks.toolbar.show_closed', count: closed_total, locale: User.find(2).language.presence || 'en')
    assert_select 'input[type=checkbox][data-switch=show-closed]:not([checked])'
    assert_select 'input[type=checkbox][data-switch=show-pending][checked]'
  end

  def test_the_switches_keep_each_other_and_the_other_settings_in_their_links
    index(zoom: 'weeks', group_by: 'tracker', show_closed: '1', show_pending: '0')
    closed_switch = css_select('input[data-switch=show-closed]').first
    pending_switch = css_select('input[data-switch=show-pending]').first
    assert closed_switch['checked'].present?
    assert pending_switch['checked'].blank?
    # turning "closed" off keeps pending off, the zoom and the grouping
    assert_match(/show_closed=0/, closed_switch['data-href'])
    assert_match(/show_pending=0/, closed_switch['data-href'])
    assert_match(/zoom=weeks/, closed_switch['data-href'])
    assert_match(/group_by=tracker/, closed_switch['data-href'])
    assert_match(/show_pending=1/, pending_switch['data-href'])
    assert_match(/show_closed=1/, pending_switch['data-href'])
  end

  # --- page weight: classes instead of inline styles, one shared grid,
  # no per-row forms or event handlers, behavior in a cacheable file

  def test_the_timeline_grid_is_one_shared_background
    index(show_closed: '1')
    rows = css_select('tr.issue-row').size
    assert rows >= 3
    assert_equal rows, css_select('td.sq-track').size
    assert_equal 1, response.body.scan('background-image:').size, 'the grid background is defined once, not per row'
    assert_equal 0, css_select('td.sq-track[style*="gradient"]').size
    assert_equal 0, css_select('div.timeline-grid').size
  end

  def test_the_screens_load_their_style_and_script_as_files
    %w[timeline matrix].each do |view|
      index(view: view)
      # Redmine 6 serves plugin assets with a digest in the name (long-lived caching)
      assert_select 'link[href*="plugin_assets/redmine_sequential_tasks/sequential_tasks-"][href$=".css"]'
      assert_select 'script[src*="plugin_assets/redmine_sequential_tasks/sequential_tasks-"][src$=".js"]'
      assert_equal 0, css_select('script:not([src]):not([type])').select { |sc| sc.text.include?('renderLightningLine') }.size,
                   'no copy of the behavior in the page'
    end
  end

  def test_rows_carry_no_per_row_forms_or_event_handlers
    %w[timeline matrix].each do |view|
      index(view: view, show_closed: '1')
      outside_template = css_select('#sq-root form').reject { |f| f.ancestors.any? { |a| a.name == 'template' } }
      assert_equal 0, outside_template.size, 'the branch form is built on demand from one template'
      assert_equal 0, css_select('tr.sq-branch-row').size
      assert_equal 1, css_select('template#sq-branch-template').size
      assert_equal 0, css_select('#sq-root [onmouseover], #sq-root [onmouseout], #sq-root .sq-bar[onclick]').size
    end
  end

  def test_the_lightning_layer_is_set_in_the_stylesheet
    index
    assert_select '#lightning-svg'
    assert_equal 0, css_select('#lightning-svg[style*="z-index"]').size, 'the layer order lives in the stylesheet'
  end

  def test_the_branch_template_is_only_for_users_who_may_add_issues
    @request.session[:user_id] = nil
    index
    assert_equal 0, css_select('template#sq-branch-template').size
    assert_equal 0, css_select('a.sq-plus').size
  end

  def test_a_row_stays_small
    index(show_closed: '1')
    timeline_row = css_select('tr.issue-row').map { |r| r.to_s.bytesize }.max
    index(view: 'matrix', show_closed: '1')
    matrix_row = css_select('tr.issue-row').map { |r| r.to_s.bytesize }.max
    # before this change a row was about 7KB (timeline) and 8KB (matrix) plus a 2.6KB hidden form row
    assert timeline_row < 3500, "timeline row is #{timeline_row} bytes"
    assert matrix_row < 3500, "matrix row is #{matrix_row} bytes"
  end

  # "Today" on the timeline is the user's today (review A-7)
  def test_the_timeline_marks_the_users_today
    zone = ['Pacific/Kiritimati', 'Pacific/Pago_Pago'].find { |z| Time.now.in_time_zone(z).to_date != Date.today }
    assert zone, 'one of the two zones has another date than the server'
    User.find(2).pref.update!(time_zone: zone)
    index(zoom: 'days')
    marked = css_select('th.sq-today .sq-d1').map { |d| d.text.strip }
    assert_equal [User.find(2).today.day.to_s], marked
  end

  # --- the area above the table stays put; only the tasks scroll (the table header and the group headers stick)

  def test_the_timeline_scrolls_inside_one_container_with_sticky_header_cells
    index
    assert_select '#timeline-scroll-container.sq-scroller'
    assert_select 'thead th.sq-th-issue'
    assert_select 'thead th.sq-th-state'
    assert css_select('thead th.sq-th-slot').any?
    assert_equal 0, css_select('#timeline-scroll-container[style*="overflow"]').size, 'scrolling is defined in the stylesheet'
    assert_equal 0, css_select('thead tr[style]').size, 'the header row has no inline border or height'
  end

  def test_group_headers_use_classes_so_they_can_stick
    index(group_by: 'tracker')
    headers = css_select('tr.group-header-row')
    assert headers.any?
    assert_equal headers.size, css_select('tr.group-header-row th.sq-gh').size
    assert_equal headers.size, css_select('tr.group-header-row td.sq-gh-fill').size
    assert_equal 0, css_select('tr.group-header-row[style], tr.group-header-row [style]').size
  end

  def test_the_matrix_has_one_scroller_and_no_scrolling_wrappers_inside
    index(view: 'matrix')
    assert_select '.sequential-matrix-container.sq-scroller'
    assert_equal 0, css_select('.tracker-matrix-section [style*="overflow-x"]').size
    assert_equal 0, css_select('.tracker-matrix-section[style*="overflow: hidden"]').size, 'hidden overflow would stop the sticky header'
    assert css_select('table.sq-mx thead th.sq-th-step').any?
  end

  # --- assignee names follow the plugin setting "name_order"

  def assignee_text(issue)
    row = css_select('tr.issue-row').find { |r| r.css("a.sq-subj[href='/issues/#{issue.id}']").any? }
    row.at_css('.sq-asg').text.strip
  end

  def test_assignee_names_follow_the_name_order_setting
    assigned = Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'assigned issue', assigned_to_id: 2)
    user = User.find(2)
    { 'first_last' => "#{user.firstname} #{user.lastname}", 'last_first' => "#{user.lastname} #{user.firstname}" }.each do |order, expected|
      Setting.plugin_redmine_sequential_tasks = { 'name_order' => order }
      %w[timeline matrix].each do |view|
        index(view: view)
        assert_equal expected, assignee_text(assigned), "#{order} in the #{view}"
      end
    end
  end

  def test_group_titles_by_assignee_follow_the_name_order_setting
    Issue.generate!(project_id: 1, tracker_id: 1, status_id: 1, subject: 'assigned issue', assigned_to_id: 2)
    user = User.find(2)
    Setting.plugin_redmine_sequential_tasks = { 'name_order' => 'last_first' }
    index(group_by: 'assigned_to')
    titles = css_select('tr.group-header-row th.sq-gh').map { |th| th.text.gsub(/\s+/, ' ') }
    assert titles.any? { |t| t.include?("#{user.lastname} #{user.firstname}") }, titles.inspect
  end

  def test_the_full_view_switch_is_in_the_toolbar_of_both_screens_and_the_frame_is_a_class
    index
    assert_select 'input[type=checkbox][data-act=full-view]:not([checked])'
    assert_select '#sq-root .sq-frame'
    assert_equal 0, css_select('#sq-root .sq-frame[style]').size, 'the frame is styled by the stylesheet so that the full view can lift it'
    index(view: 'matrix')
    assert_select 'input[data-act=full-view]'
  end

  # the adjust mode of the timeline
  def test_the_timeline_carries_what_the_adjust_mode_needs
    index
    assert_select '.sq-adjust-btn[aria-pressed=false]'
    assert_select '#sq-root[data-adjust-url] .sq-adjust-bar[hidden] input[name=sq-adjust-mode][value=fixed_due][checked]'
    stages = @active.issue_stages.order(:position).to_a
    assert_select "tr.issue-row[data-id='#{@active.id}'][data-adj^='#{stages.first.id}:'][data-due][data-start-ok='1']"
    assert_select "tr.issue-row[data-id='#{@active.id}'] .sq-bar[data-sid='#{stages.first.id}']"
  end

  def test_no_adjust_mode_without_the_right_to_edit_issues
    Role.find(1).remove_permission!(:edit_issues) # jsmith's role in ecookbook
    index
    assert_select '.sq-adjust-btn', 0
    assert_select 'tr.issue-row[data-adj]', 0
  end

  def test_no_adjust_mode_in_the_matrix
    index(view: 'matrix')
    assert_select '.sq-adjust-btn', 0
  end

  # the matrix as CSV
  def csv_rows(params = {})
    get :index, params: { project_id: 'ecookbook', format: 'csv', encoding: 'UTF-8' }.merge(params)
    assert_response :success
    assert_match %r{\Atext/csv}, response.media_type
    CSV.parse(response.body.sub("\xEF\xBB\xBF", ''))
  end

  def test_csv_is_the_matrix_one_block_per_tracker_with_five_columns_per_stage
    rows = csv_rows
    assert_equal [I18n.t('sequential_tasks.table.group_tracker', name: Tracker.find(1).name, locale: :en)], rows[0], 'the tracker title row'
    header = rows[1]
    assert_equal '#', header.first
    assert_equal 10 + 3 * 5, header.size, 'the issue columns, then 5 for each of the 3 stages'
    assert_equal "#{IssueStatus.find(1).name} planned start", header[10]
    ids = rows.drop(2).map { |r| r.first.to_i }
    assert_includes ids, @active.id
    refute_includes ids, @closed.id, 'finished issues are hidden on the screen, so in the CSV too'
    active = rows.find { |r| r.first.to_i == @active.id }
    assert_equal 'active issue', active[2]
    first = @active.issue_stages.order(:position).first
    assert_equal I18n.l(first.planned_start_date), active[10]
  end

  def test_csv_follows_the_screen_switches
    ids = csv_rows(show_closed: '1').drop(2).map { |r| r.first.to_i }
    assert_includes ids, @closed.id
  end

  def test_csv_in_japanese_is_shift_jis_like_redmines_own
    User.find(2).update!(language: 'ja')
    get :index, params: { project_id: 'ecookbook', format: 'csv' }
    assert_response :success
    text = response.body.dup.force_encoding('CP932').encode('UTF-8')
    assert_includes text, "#{IssueStatus.find(1).name} 予定開始"
  end

  def test_the_csv_link_is_on_the_matrix_only
    index(view: 'matrix')
    assert_select 'p.other-formats a[href*=".csv"]', minimum: 1
    index
    assert_select 'p.other-formats a[href*=".csv"]', 0
  end

  # the adjust mode is not offered without any working day
  def test_no_adjust_mode_without_any_working_day
    Setting.non_working_week_days = %w[1 2 3 4 5 6 7]
    index
    assert_select '.sq-adjust-btn', 0
  end

  # Review 2026-11-14: a subject that a spreadsheet would take as a formula stays text
  def test_csv_keeps_a_formula_like_subject_as_text
    @active.update!(subject: '=HYPERLINK("http://example.com","x")')
    active = csv_rows.find { |r| r.first.to_i == @active.id }
    assert_equal %q('=HYPERLINK("http://example.com","x")), active[2]
  end
end
