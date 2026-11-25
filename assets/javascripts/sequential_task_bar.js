/*
 * Sequential Tasks: the stage timeline on the issue page and its "adjust the schedule".
 * Moved out of the page (review 2026-11-14): no inline script or event attributes; the page gives its settings in
 * data attributes (#sq-stage-timeline: data-non-working; #sq-bamboo-bar: data-orig-due and the unit words) and
 * the controls are found by id and class. The date calculation is SqDates (sequential_dates.js), shared with the
 * project timeline and the same rules as the server.
 */
(function () {
  'use strict';

  var STAGE_DAY_PX = 10; // each day after the first adds this much to a stage box
  var D = window.SqDates;

  function $(id) { return document.getElementById(id); }
  function each(list, fn) { Array.prototype.forEach.call(list, fn); }
  function root() { return $('sq-stage-timeline'); }
  function bar() { return $('sq-bamboo-bar'); }
  function segs() { return document.querySelectorAll('#sq-bamboo-bar .stage-drag-seg'); }
  function editing() { var b = bar(); return !!(b && b.classList.contains('sq-bamboo-bar-editing')); }

  function calc() {
    var r = root();
    var off = [];
    try { off = JSON.parse((r && r.getAttribute('data-non-working')) || '[]'); } catch (e) { off = []; }
    return D.make(off);
  }

  function intOf(value, fallback) {
    var v = parseInt(value, 10);
    return (isNaN(v) || v < 1) ? fallback : v;
  }

  function segDays(seg) {
    var input = seg.querySelector('.stage-duration-input');
    return intOf(input && editing() ? input.value : seg.getAttribute('data-orig-duration'), 1);
  }

  function segAllDays(seg) {
    var box = seg.querySelector('.stage-all-days');
    return box ? box.checked : seg.getAttribute('data-all-days') === '1';
  }

  function fixedDueMode() {
    var checked = document.querySelector('#stage-mode-switch input[name="mode"]:checked');
    return !checked || checked.value === 'fixed_due'; // without a switch (one adjustable stage) the server pushes
  }

  // ---- the width of each box: its own no-wrap width + STAGE_DAY_PX x (days - 1) -------------------

  function measureBases() {
    var b = bar();
    if (!b) return;
    var list = segs();
    var was = editing();
    function widths(on) {
      b.classList.toggle('sq-bamboo-bar-editing', on);
      each(list, function (seg) { seg.style.width = 'max-content'; });
      return Array.prototype.map.call(list, function (seg) { return Math.ceil(seg.getBoundingClientRect().width); }); // written all, then read all
    }
    var plain = widths(false);
    var edit = widths(true);
    b.classList.toggle('sq-bamboo-bar-editing', was);
    each(list, function (seg, i) { seg.setAttribute('data-base-px', Math.max(plain[i], edit[i])); });
  }

  function sizeSegs() {
    each(segs(), function (seg) {
      var base = parseInt(seg.getAttribute('data-base-px'), 10);
      if (!isNaN(base)) seg.style.width = (base + STAGE_DAY_PX * (segDays(seg) - 1)) + 'px';
    });
  }

  // ---- the preview while adjusting ---------------------------------------------------------------------------

  var fits = true;
  var startTooLate = false; // due date first: the new start leaves the first stage no day
  var lastPlan = {}; // stage id -> { start, end } as last drawn: what a change of the start or the counting keeps
  var initial = null; // the form as it was opened: a change makes leaving the page ask first

  function formState() {
    var form = $('sequential-task-stage-edit-form');
    if (!form) return '';
    var parts = [];
    each(form.elements, function (el) {
      if (!el.name || el.disabled) return;
      if ((el.type === 'radio' || el.type === 'checkbox') && !el.checked) return;
      parts.push(el.name + '=' + el.value);
    });
    return parts.join('&');
  }

  function recalc() {
    var c = calc();
    var b = bar();
    if (!b) return;
    var startInput = $('stage-start-input');
    var newStart = (startInput && !startInput.disabled && startInput.value) ? c.next(D.dayNumber(startInput.value)) : null;
    var startPill = document.querySelector('#stage-start-pill .stage-start-date');
    if (startPill && newStart !== null) startPill.textContent = D.mmdd(newStart);

    var all = Array.prototype.slice.call(segs());
    var adjustable = all.filter(function (seg) { return seg.getAttribute('data-fixed') === '0'; });
    var first = adjustable[0];
    var start = newStart !== null ? newStart : (first ? c.next(D.dayNumber(first.getAttribute('data-start'))) : null);
    var stages = adjustable.map(function (seg) { return { id: seg.getAttribute('data-stage-id'), all: segAllDays(seg), seg: seg }; });
    var days = {};
    stages.forEach(function (st) { days[st.id] = segDays(st.seg); });

    // "Due date first": the slack's days are what is left up to the unchanged end of the plan
    fits = true;
    var slackSeg = document.querySelector('#sq-bamboo-bar .stage-drag-seg[data-slack="1"]');
    if (fixedDueMode() && slackSeg && start !== null) {
      var slack = stages[stages.length - 1];
      var r = c.slackDays(stages.slice(0, -1), slack, start, days, D.dayNumber(b.getAttribute('data-orig-due')));
      fits = r.fits;
      days[slack.id] = r.days;
      slackSeg.querySelector('.stage-duration-input').value = r.days;
    }

    var lastEnd = null;
    all.forEach(function (seg) { if (seg.getAttribute('data-fixed') === '1') lastEnd = D.dayNumber(seg.getAttribute('data-end')); });
    if (startTooLate) fits = false;
    if (start !== null) {
      var keep = !startTooLate; // a start that does not fit is not remembered: moving it back restores the plan
      if (keep) lastPlan = {};
      c.layout(stages, start, days).forEach(function (p, i) {
        if (keep) lastPlan[p.id] = { start: p.start, end: p.end };
        var seg = stages[i].seg;
        var unit = seg.querySelector('.stage-days-unit'); // "working days" or "days"
        if (unit) unit.textContent = b.getAttribute(stages[i].all ? 'data-t-all-days' : 'data-t-working');
        var pill = document.querySelector('#stage-plan-pill-' + p.id + ' .stage-plan-date');
        if (pill) pill.textContent = D.mmdd(p.end);
        lastEnd = p.end;
      });
    }
    if (lastEnd !== null) {
      var total = $('preview-total-due-date');
      if (total) total.textContent = D.slashed(lastEnd);
      var due = document.querySelector('#stage-due-pill .stage-due-date');
      if (due) due.textContent = D.mmdd(lastEnd);
    }

    // Does not fit: say so where it is saved, and the save button cannot be pressed (review 2026-11-14)
    var dueNote = $('preview-total-due-date');
    if (dueNote) dueNote.style.color = fits ? '#2563eb' : '#dc2626';
    var hint = document.querySelector('.stage-slack-note');
    if (hint) hint.style.display = fits ? 'none' : 'inline';
    var save = $('stage-save-button');
    if (save) save.disabled = !fits;
    var why = $('stage-cannot-fit');
    if (why) why.hidden = fits;
    sizeSegs();
  }

  // ---- opening, cancelling, the mode ------------------------------------------------------------------------

  function setOpen(open) {
    var controls = $('stage-edit-controls');
    if (!controls) return;
    controls.style.display = open ? 'block' : 'none';
    var b = bar();
    if (b) b.classList.toggle('sq-bamboo-bar-editing', open);
    var sw = $('stage-mode-switch');
    if (sw) sw.style.display = open ? 'inline-flex' : 'none';
    each(document.querySelectorAll('.sq-adjust-toggle'), function (btn) { btn.setAttribute('aria-expanded', open ? 'true' : 'false'); });
    if (open) {
      modeChanged();
      initial = formState();
    } else {
      // Cancel: the typed or dragged values and the mode back as they were, the callouts and widths too
      var form = $('sequential-task-stage-edit-form');
      if (form) form.reset();
      startTooLate = false;
      modeChanged();
      initial = null;
    }
  }

  function modeChanged() {
    var checked = document.querySelector('#stage-mode-switch input[name="mode"]:checked');
    var hint = $('stage-mode-hint'); // the selected mode in words (read out when it changes)
    if (hint) hint.textContent = checked ? (checked.closest('label').getAttribute('data-hint') || '') : '';
    var handle = document.querySelector('.stage-drag-handle-slack');
    if (handle) handle.style.visibility = fixedDueMode() ? 'hidden' : 'visible'; // the due date edge stays in fixed_due
    recalc();
  }

  function toggleBranch() {
    var panel = $('branch-create-form-panel');
    if (!panel) return;
    var open = panel.style.display === 'none' || panel.style.display === '';
    panel.style.display = open ? 'block' : 'none';
    if (open) {
      var input = $('panel-branch-subject');
      if (input) { input.focus(); input.select(); }
    }
  }

  // ---- "due date first" trades days across ONE boundary ------------------------------------
  // Changing a stage (dragging its right edge or typing its days) gives or takes the days from the next adjustable
  // stage only (for the last one, the stage before it), keeping the pair's total; the next stage never drops under
  // 1 day on a drag. "Days first": only that stage changes and the rest moves along.

  var pair = null; // { input, other, total }

  function partnerOf(input) {
    var list = Array.prototype.slice.call(segs());
    var i = list.indexOf(input.closest('.stage-drag-seg'));
    var isAdj = function (seg) { return seg.getAttribute('data-fixed') === '0'; };
    var other = list.slice(i + 1).filter(isAdj)[0] || (fixedDueMode() ? list.slice(0, i).reverse().filter(isAdj)[0] : null);
    return other ? other.querySelector('.stage-duration-input') : null;
  }

  function startPair(input) {
    var other = partnerOf(input);
    pair = other ? { input: input, other: other, total: intOf(input.value, 1) + intOf(other.value, 1) } : null;
  }

  function pairEdit(input) {
    if (fixedDueMode() && pair && pair.input === input) {
      var raw = parseInt(input.value, 10);
      if (!isNaN(raw) && raw >= 1) pair.other.value = Math.max(pair.total - raw, 1);
    }
    recalc();
  }

  var dragging = null; // { input, startX, startDays, lastDays }

  // ---- the listeners -----------------------------------------------------------------------------------------

  document.addEventListener('click', function (e) {
    var act = e.target.closest && e.target.closest('[data-sq-act]');
    if (!act || !root() || !root().contains(act)) return;
    if (act.getAttribute('data-sq-act') === 'adjust') setOpen(!editing());
    else if (act.getAttribute('data-sq-act') === 'branch') toggleBranch();
  });

  // "Due date first" (2026-11-15): a new start date is the left boundary of the first stage, so the first stage takes
  // it up (its end stays; less than 1 day does not fit); switching "count non-working days" keeps the stage's dates and
  // counts its days again, so nothing else moves. "Days first": the plan shifts / the stage keeps its count.
  function startChanged(input) {
    var first = document.querySelector('#sq-bamboo-bar .stage-drag-seg[data-fixed="0"]');
    startTooLate = false;
    if (fixedDueMode() && first && input.value && lastPlan[first.getAttribute('data-stage-id')] && document.querySelector('#stage-mode-switch')) {
      var c = calc();
      var end = lastPlan[first.getAttribute('data-stage-id')].end;
      var n = c.daysBetween(c.next(D.dayNumber(input.value)), end, segAllDays(first));
      startTooLate = n < 1;
      first.querySelector('.stage-duration-input').value = Math.max(n, 1);
    }
    recalc();
  }

  function countingChanged(box) {
    var seg = box.closest('.stage-drag-seg');
    var plan = seg && lastPlan[seg.getAttribute('data-stage-id')];
    if (fixedDueMode() && plan && document.querySelector('#stage-mode-switch')) {
      seg.querySelector('.stage-duration-input').value = Math.max(calc().daysBetween(plan.start, plan.end, box.checked), 1);
    }
    recalc();
  }

  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t.matches) return;
    if (t.matches('#stage-mode-switch input[name="mode"]')) modeChanged();
    else if (t.matches('#sq-stage-timeline .stage-all-days')) countingChanged(t);
    else if (t.matches('#stage-start-input')) startChanged(t);
  });

  document.addEventListener('input', function (e) {
    var t = e.target;
    if (!t.matches) return;
    if (t.matches('#sq-stage-timeline .stage-duration-input')) pairEdit(t);
    else if (t.matches('#stage-start-input')) startChanged(t);
  });

  document.addEventListener('focusin', function (e) {
    if (e.target.matches && e.target.matches('#sq-stage-timeline .stage-duration-input')) startPair(e.target);
  });

  // Esc closes adjusting (asking first when something was changed); Enter in a day box recalculates, it does not send
  // the form (review 2026-11-14)
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && editing() && !dragging) {
      if (initial !== null && formState() !== initial && !window.confirm(root().getAttribute('data-t-discard') || '')) return;
      setOpen(false);
      var toggle = document.querySelector('.sq-adjust-toggle');
      if (toggle) toggle.focus();
      return;
    }
    if (e.key === 'Enter' && e.target.matches && e.target.matches('#sq-stage-timeline .stage-duration-input, #stage-start-input')) {
      e.preventDefault();
      recalc();
    }
  });

  var submitting = false;
  document.addEventListener('submit', function (e) {
    if (e.target.id !== 'sequential-task-stage-edit-form') return;
    if (!fits) { e.preventDefault(); return; }
    submitting = true;
  });

  // Leaving the page with changes that were not saved asks first (review 2026-11-14)
  window.addEventListener('beforeunload', function (e) {
    if (submitting || !editing() || initial === null || formState() === initial) return;
    e.preventDefault();
    e.returnValue = '';
  });

  document.addEventListener('pointerdown', function (e) {
    var handle = e.target.closest && e.target.closest('#sq-stage-timeline .stage-drag-handle');
    if (!handle || handle.style.visibility === 'hidden') return;
    var seg = handle.closest('.stage-drag-seg');
    var input = seg && seg.querySelector('.stage-duration-input');
    if (!input) return;
    startPair(input);
    var days = intOf(input.value, 1);
    dragging = { input: input, startX: e.clientX, startDays: days, lastDays: days };
    try { handle.setPointerCapture(e.pointerId); } catch (err) { /* a synthetic event */ }
    e.preventDefault();
  });

  document.addEventListener('pointermove', function (e) {
    if (!dragging) return;
    var days = Math.max(dragging.startDays + Math.round((e.clientX - dragging.startX) / STAGE_DAY_PX), 1); // the edge follows the pointer
    if (fixedDueMode() && pair && pair.input === dragging.input) days = Math.min(days, pair.total - 1);
    if (days === dragging.lastDays) return; // nothing to redraw until a whole day changes
    dragging.lastDays = days;
    dragging.input.value = days;
    pairEdit(dragging.input);
  });

  document.addEventListener('pointerup', function () { dragging = null; });
  document.addEventListener('pointercancel', function () { dragging = null; });

  // ---- start-up ----------------------------------------------------------------------------------------------

  function init() {
    if (!bar()) return;
    measureBases();
    sizeSegs();
  }

  init(); // the script comes after the bar and its stylesheet
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(init); // again once the fonts are in
  window.SqStageBar = { open: function () { setOpen(true); }, close: function () { setOpen(false); }, recalc: recalc, fits: function () { return fits; } }; // (for tests and measurements)
})();
