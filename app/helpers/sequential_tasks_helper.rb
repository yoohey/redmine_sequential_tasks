# frozen_string_literal: true

# Helpers of the project screens: controls of the toolbar, and the cells of an issue row.
#
# The toolbar controls carry data attributes only: sequential_tasks.js follows the links (a data-nav select goes to
# the selected option's value, a switch to its data-href).
#
# The row cells are built as plain strings, not with partials or link_to: a screen can have hundreds of rows and
# these were measured as the slow part. Every piece that comes from
# data goes through h(); the string is marked html_safe once, at the end.
module SequentialTasksHelper
  # Texts and settings that every row of a screen needs, formed once
  RowContext = Struct.new(:parent_tip, :oos_tip, :plus_tip, :unassigned, :issue_base, :name_order, :can_add,
                          :can_reorder, :states, :delayed_tpl, :orphan_tip, :release_ok_tpl, :release_late_tpl, :release_chip_tpl, :status_names)

  def sq_row_context
    outside = @outside_parents
    RowContext.new(
      l('sequential_tasks.branch.tooltip_with_parent', id: '%s'),
      l('sequential_tasks.out_of_stage.tooltip'),
      l('sequential_tasks.branch.create_title'),
      l('sequential_tasks.table.unassigned_short'),
      issue_path(0).chomp('0'), # the link to an issue is built by hand
      RedmineSequentialTasks::NameFormat.order, # how assignee names are written (plugin setting)
      !@inline && User.current.allowed_to?(:add_issues, @project), # (the inline view has no forms)
      @can_reorder,
      { closed: l('sequential_tasks.state.closed'), pending: l('sequential_tasks.state.pending'),
        ahead: l('sequential_tasks.state.ahead'), in_progress: l('sequential_tasks.state.in_progress') },
      l('sequential_tasks.state.delayed', days: '%d'),
      # a branch whose parent is not in the list: the tip names the parent when the user may see it
      lambda do |pid|
        parent = outside[pid]
        if parent
          l('sequential_tasks.branch.orphan_tip', id: pid, subject: parent.subject, status: parent.status.name)
        else
          l('sequential_tasks.branch.orphan_tip_plain', id: pid)
        end
      end,
      l('sequential_tasks.release.ok_title', name: '%s', date: '%s', days: '%d'),
      l('sequential_tasks.release.late_title', name: '%s', date: '%s', days: '%d'),
      l('sequential_tasks.release.chip', days: '%d'),
      @status_names || {}
    )
  end

  # The left cell of a row: the tree mark (or the chip of an unlisted parent), the status chip, the subject, the
  # assignee, the drag handle (reorder mode) and the +branch button.
  # indent - pixels per level; oos_chip - show the "no stage for this status" mark in the chip (timeline)
  # release - the release outlook of the issue (see the controller) or nil: an issue that will miss its release gets a
  # small chip with the days
  # slow - the slowness outlook of the issue (see the controller) or nil: a chip "usual x1.8" when it stays much longer
  # in its current stage than the issues before it did
  # branch - { total:, closed: } of its branches or nil: a small mark "closed/total" (green when all are done, orange
  # when the issue itself is done but branches are open)
  def sq_issue_cell(issue, summary, level, parent_id, ctx, indent:, oos_chip:, release: nil, branch: nil, slow: nil, wait: nil)
    html = +''
    html << '<td class="sq-sticky sq-c-issue"'
    html << %( style="padding-left: #{8 + (level * indent)}px") if level.positive?
    html << '><div class="sq-ib">'
    if level.positive?
      html << %(<span class="sq-tree" title="#{h(ctx.parent_tip % parent_id)}">└─ 🌿</span>)
    elsif parent_id
      html << %(<a class="sq-orphan" href="#{ctx.issue_base}#{parent_id}" title="#{h(ctx.orphan_tip.call(parent_id))}">🌿 ↰ ##{parent_id}</a>)
    end
    if oos_chip && summary.out_of_stage?
      html << %(<span class="sq-chip sq-chip-oos" title="#{h(ctx.oos_tip)}">⚑ #{h(issue.status.name)}</span>)
    else
      html << %(<span class="sq-chip">#{h(issue.status.name)}</span>)
    end
    html << %(<a class="sq-subj" href="#{ctx.issue_base}#{issue.id}">##{issue.id} #{h(issue.subject)}</a>)
    if wait # the issue is still in a stage of zero days: nobody has picked it up
      html << %(<span class="sq-wait-chip" title="#{h(l('sequential_tasks.zero_day.title', days: wait))}">#{h(wait.positive? ? l('sequential_tasks.zero_day.chip', days: wait) : l('sequential_tasks.zero_day.chip_today'))}</span>)
    end
    if release && release[:margin].negative?
      title = format(ctx.release_late_tpl, release[:name], RedmineSequentialTasks::DateFormat.full(release[:date]), -release[:margin])
      html << %(<span class="sq-rl" title="#{h(title)}">#{h(format(ctx.release_chip_tpl, -release[:margin]))}</span>)
    end
    if issue.assigned_to
      name = h(RedmineSequentialTasks::NameFormat.name(issue.assigned_to, ctx.name_order))
      html << %(<span class="sq-asg" title="#{name}">#{name}</span>)
    else
      html << %(<span class="sq-asg sq-none">#{h(ctx.unassigned)}</span>)
    end
    html << sq_slow_chip(slow, ctx) if slow
    html << sq_branch_mark(branch, summary) if branch
    html << '<span class="sq-hd" draggable="true">⠿</span>' if ctx.can_reorder
    html << %(<a href="#" class="sq-plus" title="#{h(ctx.plus_tip)}">+🌿</a>) if ctx.can_add
    html << '</div></td>'
    html.html_safe
  end

  # "usual x1.8"
  def sq_slow_chip(slow, ctx)
    title = l('sequential_tasks.slowness.title', stage: ctx.status_names[slow[:stage]], elapsed: slow[:elapsed], median: number_with_precision(slow[:median], precision: 1, strip_insignificant_zeros: true),
                                                  count: slow[:count], ratio: slow[:ratio])
    %(<span class="sq-sl" title="#{h(title)}">#{h(l('sequential_tasks.slowness.chip', ratio: format('%.1f', slow[:ratio])))}</span>)
  end

  # "2/3": how many of the branches are done
  def sq_branch_mark(branch, summary)
    open_count = branch[:total] - branch[:closed]
    kind = if open_count.zero? then ' sq-bc-done'
           elsif summary.closed? then ' sq-bc-warn'
           end
    title = l('sequential_tasks.branch.progress_title', total: branch[:total], closed: branch[:closed])
    title += " #{l('sequential_tasks.branch.progress_warn', open: open_count)}" if kind == ' sq-bc-warn'
    %(<span class="sq-bc#{kind}" title="#{h(title)}">#{branch[:closed]}/#{branch[:total]}</span>)
  end

  # The state cell: the badge (finished, delayed, not started, ahead, in progress).
  # oos_note - the matrix names a status without a stage under the badge
  def sq_state_cell(issue, summary, ctx, oos_note:)
    kind, text = if summary.closed? then [:closed, ctx.states[:closed]]
                 elsif summary.delayed? then [:delayed, format(ctx.delayed_tpl, summary.delay_days)]
                 elsif summary.pending? then [:pending, ctx.states[:pending]]
                 elsif summary.ahead? then [:ahead, ctx.states[:ahead]]
                 else [nil, ctx.states[:in_progress]]
                 end
    html = +''
    html << %(<td class="sq-sticky sq-c-state"><span class="sq-sb#{" sq-sb-#{kind}" if kind}">#{h(text)}</span>)
    html << %(<div class="sq-oos" title="#{h(ctx.oos_tip)}">⚑ #{h(issue.status.name)}</div>) if oos_note && summary.out_of_stage?
    html << '</td>'
    html.html_safe
  end

  # The switch between the screens of the project: timeline, matrix and analysis. list_path - how a link of the
  # timeline or the matrix is built (keeping the settings of the page), or nil on the analysis screen
  def sq_view_switch(project, current, list_path = nil)
    path = list_path || ->(overrides) { project_sequential_tasks_path(project, overrides) }
    sq_segment([["📊 #{l('sequential_tasks.view.timeline')}", path.call(view: 'timeline'), current == 'timeline'],
                ["📋 #{l('sequential_tasks.view.matrix')}", path.call(view: 'matrix'), current == 'matrix'],
                ["📈 #{l('sequential_tasks.view.analysis')}", project_sequential_task_analysis_path(project), current == 'analysis']])
  end

  # Buttons that act as one control: items are [text, url, active]
  def sq_segment(items)
    content_tag(:div, class: 'sq-seg') do
      safe_join(items.map { |text, url, active| link_to(text, url, class: ('sq-active' if active)) })
    end
  end

  # A labelled dropdown whose options are links: options are [text, url, selected]; name marks the select (data-<name>)
  def sq_dropdown(label, name, options)
    choices = options.map { |text, url, selected| content_tag(:option, text, value: url, selected: selected) }
    content_tag(:div, class: 'sq-field') do
      content_tag(:span, label) + content_tag(:select, safe_join(choices), class: 'sq-select', data: { name => true, nav: true })
    end
  end

  # A checkbox that goes to a link when it is changed
  def sq_switch(name, label, checked, url)
    content_tag(:label, class: 'sq-check') do
      tag(:input, type: 'checkbox', checked: checked, data: { switch: name, href: url }) + " #{label}".html_safe
    end
  end
end
