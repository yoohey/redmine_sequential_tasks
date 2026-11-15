# frozen_string_literal: true

# Standalone test (no Redmine test DB needed): ruby test/unit/stylesheet_test.rb
# The table header, its left corner and the group headers must stick while the tasks scroll
# inside the container (the page itself does not scroll).
require 'minitest/autorun'

class StylesheetTest < Minitest::Test
  CSS = File.read(File.expand_path('../../assets/stylesheets/sequential_tasks.css', __dir__))

  # all declarations of the rules whose selector mentions the fragment
  def declarations(fragment)
    CSS.scan(/([^{}]+)\{([^{}]*)\}/m).select { |selector, _| selector.include?(fragment) }.map(&:last).join(' ')
  end

  # a finished stage is pale, the current one stands out (white text on the color), a coming one is dashed
  def test_a_finished_stage_is_paler_than_the_current_one
    # the state rules are shared with the stage timeline on the issue page: :is(#sq-root, #sq-stage-timeline)
    done = CSS[/:is\(#sq-root, #sq-stage-timeline\) \.sq-bar-done \{[^}]*\}/]
    assert_match(/color-mix\(in srgb, var\(--c\) \d+%, #fff\)/, done, 'the finished bar is the stage color mixed with white')
    refute_match(/background: var\(--c\)/, done)
    assert_match(/#sq-stage-timeline\) \.sq-bar-cur[^{]*\{[^}]*color: #fff/, CSS, 'the current bar keeps its strong look')
    assert_match(/\.sq-bar-future \{[^}]*dashed/, CSS, 'a coming stage stays dashed')
  end

  def test_the_scroller_scrolls_in_both_directions
    body = declarations('.sq-scroller')
    assert_match(/overflow: auto/, body)
    assert_match(/max-height:/, body, 'a default height; the script sets the real one from the window height')
  end

  def test_the_table_runs_down_to_the_footer
    assert_match(/padding-bottom: 0/, declarations('#content:has(#sq-root)'), 'no padding between the table and the footer')
  end

  def test_the_header_cells_stick_to_the_top
    %w[th.sq-th-slot th.sq-th-issue th.sq-th-state].each do |selector|
      body = declarations(selector)
      assert_match(/position: sticky/, body, "#{selector} is sticky")
      assert_match(/top: 0/, body, "#{selector} sticks to the top")
    end
  end

  def test_the_left_corner_is_above_the_other_header_cells
    corner = declarations('th.sq-th-issue')[/z-index: (\d+)/, 1].to_i
    slot = declarations('th.sq-th-slot')[/z-index: (\d+)/, 1].to_i
    assert corner > slot
  end

  def test_group_headers_stick_right_below_the_table_header
    body = declarations('.sq-gh')
    assert_match(/position: sticky/, body)
    assert_match(/top: var\(--sq-head-h/, body, 'below the table header, whose height the script measures')
  end

  def z(selector)
    declarations(selector)[/z-index: (\d+)/, 1].to_i
  end

  # From the bottom: bars < the fill of a group header < the lightning line < the left columns (task cells, the
  # label of a group header) < the table header < its left corner. So the line crosses the group header bands
  # and the bars, but goes under the task columns and under the date header.
  def test_the_lightning_line_goes_over_the_group_header_bands_and_under_the_left_columns
    assert z('.sq-bar') > 0
    assert z('.sq-gh-fill') > z('.sq-bar'), 'a stuck group header covers the bars that scroll under it'
    assert z('#lightning-svg') > z('.sq-gh-fill'), 'the line is above the group header band'
    assert z('td.sq-sticky') > z('#lightning-svg'), 'the left task columns are above the line'
    assert z('th.sq-gh') > z('td.sq-sticky'), 'the group label covers the task cells scrolling under it'
    assert z('th.sq-th-slot') > z('th.sq-gh'), 'the date header is above everything that scrolls'
    assert z('th.sq-th-issue') > z('th.sq-th-slot')
  end

  def test_the_group_header_label_stays_above_its_fill_when_scrolled_sideways
    label = declarations('th.sq-gh')[/z-index: (\d+)/, 1].to_i
    fill = declarations('td.sq-gh-fill')[/z-index: (\d+)/, 1].to_i
    fill = declarations('.sq-gh, ')[/z-index: (\d+)/, 1].to_i if fill.zero?
    assert label > fill, 'otherwise the fill cell, later in the row, covers the label'
  end

  def test_matrix_step_headers_stick_too
    body = declarations('th.sq-th-step')
    assert_match(/position: sticky/, body)
    assert_match(/top: 0/, body)
  end

  # The drop mark of the reorder mode must show on the sticky left columns too: their vertical line is a shadow with
  # a more specific rule, so the mark has to be part of that shadow
  def test_the_drop_mark_shows_on_the_left_columns_of_the_timeline
    %w[sq-drop-before sq-drop-after].each do |mark|
      %w[sq-c-issue sq-c-state].each do |cell|
        body = declarations("tr.#{mark} > td.#{cell}")
        assert_match(/#2563eb/, body, "#{mark} on #{cell}")
        assert_match(/inset -\d+px 0 0/, body, "#{mark} on #{cell} keeps the vertical line")
      end
    end
  end

  def test_an_issue_without_an_assignee_is_red
    body = declarations('.sq-asg.sq-none')
    assert_match(/color: #b91c1c/, body)
  end

  # The full view and printing lift the scroll frame
  def test_the_full_view_lifts_the_limits_of_the_frame_and_the_scroller
    assert_match(/overflow: visible/, declarations('#sq-root.sq-full .sq-frame'))
    body = declarations('#sq-root.sq-full .sq-scroller')
    assert_match(/overflow: visible/, body)
    assert_match(/max-height: none !important/, body)
    assert_match(/position: relative/, declarations('#sq-root.sq-full th'), 'nothing sticks in the full view')
    assert_match(/overflow: visible/, declarations('#wrapper:has(#sq-root.sq-full)'), "Redmine's frames must not cut the wide table")
    assert_match(/min-width: var\(--sq-full-w/, declarations('#wrapper:has(#sq-root.sq-full)'), 'the page is as wide as the widest table')
  end

  def test_printing_gets_the_full_layout_without_the_controls
    assert_match(/@media print/, CSS)
    assert_match(/@page \{ size: landscape/, CSS)
    print_block = CSS[/@media print \{.*\z/m]
    assert_match(/#main-menu/, print_block)
    assert_match(/print-color-adjust: exact/, print_block, 'bars and badges keep their colors on paper')
    assert_match(/overflow: visible/, print_block)
  end

  # The right panel: fixed on the right, the page leaves room for it, and it is not printed
  def test_the_issue_panel_is_fixed_on_the_right_and_makes_room
    assert_match(/position: fixed/, declarations('#sq-panel'))
    assert_match(/padding-right: var\(--sq-panel-w\)/, declarations('body.sq-panel-on'))
    print_block = CSS[/@media print \{.*\z/m]
    assert_match(/#sq-panel/, print_block, 'the panel is left out of the print')
  end
end
