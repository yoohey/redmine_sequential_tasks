# frozen_string_literal: true

require File.expand_path('../../../../../test/test_helper', __FILE__)

# The prototype of the schedule with dependencies. Redmine fixtures:
# user 2 (jsmith) is a Manager of project 1.
class SequentialTaskNetworksTest < Redmine::ControllerTest
  tests SequentialTaskNetworksController

  def setup
    Setting.cross_project_issue_relations = '1'
    Project.find(1).enable_module!(:sequential_tasks)
    @a = phase('A', '2026-11-02', '2026-11-06')
    @b = phase('B', '2026-11-09', '2026-11-13')
    @c = phase('C', '2026-11-16', '2026-11-20')
    @d = phase('D', '2026-11-16', '2026-11-20')
    @alone = phase('Alone', '2026-11-02', '2026-11-06')
    [[@a, @b], [@b, @c], [@b, @d]].each { |from, to| IssueRelation.create!(issue_from: from, issue_to: to, relation_type: 'precedes', delay: 0) }
    @request.session[:user_id] = 2
  end

  def phase(subject, from, to)
    Issue.generate!(project_id: 1, tracker_id: 1, subject: subject, start_date: from, due_date: to)
  end

  def test_the_issues_tied_by_relations_are_shown_in_lanes_with_the_main_flow_on_one_lane
    get :show, params: { project_id: 'ecookbook', issue_id: @c.id } # any issue of the network will do
    assert_response :success
    assert_select 'a.sq-net-bar', 4
    assert_select 'a.sq-net-bar[href=?]', "/issues/#{@alone.id}", 0
    lanes = css_select('a.sq-net-bar').group_by { |bar| bar['data-lane'] }.transform_values(&:size)
    assert_equal({ '0' => 3, '1' => 1 }, lanes, 'A, B and C on the first lane, D under them')
  end

  def test_a_phase_after_two_phases_of_the_main_flow_is_as_thick_as_their_lanes
    after = phase('After', '2026-11-23', '2026-11-27')
    [@c, @d].each { |before| IssueRelation.create!(issue_from: before, issue_to: after, relation_type: 'precedes', delay: 0) }
    get :show, params: { project_id: 'ecookbook', issue_id: @a.id }
    assert_select "a.sq-net-bar[href=?][data-lane='0'][data-span='2']", "/issues/#{after.id}"
  end

  def test_a_phase_that_runs_alongside_is_brought_in_by_a_relates_relation_and_has_no_order
    beside = phase('Beside', '2026-11-16', '2026-11-27')
    IssueRelation.create!(issue_from: @c, issue_to: beside, relation_type: 'relates')
    get :show, params: { project_id: 'ecookbook', issue_id: @a.id }
    assert_select "a.sq-net-bar[href=?]", "/issues/#{beside.id}"
    assert_select 'svg.sq-net-edges line', 1 # still only B -> D: "relates" draws no line
  end

  def test_a_dependency_that_is_not_next_to_it_gets_a_light_line
    get :show, params: { project_id: 'ecookbook', issue_id: @a.id }
    assert_select 'svg.sq-net-edges line', 1 # B -> D (B and C touch on one lane: the arrow shape says it)
  end

  def test_an_issue_without_dates_is_left_out_and_named
    undated = Issue.generate!(project_id: 1, tracker_id: 1, subject: 'No dates')
    IssueRelation.create!(issue_from: @d, issue_to: undated, relation_type: 'precedes', delay: 0) # Redmine dates the following issue
    undated.update_columns(start_date: nil, due_date: nil)
    get :show, params: { project_id: 'ecookbook', issue_id: @a.id }
    assert_select 'a.sq-net-bar', 4
    assert_select 'p.info', text: /##{undated.id}/
  end

  def test_without_an_issue_only_the_form_is_shown
    get :show, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_select 'form input#issue_id'
    assert_select 'a.sq-net-bar', 0
  end

  def test_an_unknown_issue_says_so
    get :show, params: { project_id: 'ecookbook', issue_id: 999_999 }
    assert_select 'p.nodata'
  end

  def test_nothing_is_shown_when_the_module_is_off
    Project.find(1).disable_module!(:sequential_tasks)
    get :show, params: { project_id: 'ecookbook', issue_id: @a.id }
    assert_response :forbidden
  end
end
