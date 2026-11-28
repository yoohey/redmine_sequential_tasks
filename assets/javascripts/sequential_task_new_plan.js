/*
 * Sequential Tasks: the stage timeline in the form of a new issue (planning the stages while creating).
 * The bar uses the issue page's ids and classes for its look; this script only runs where the bar has the class
 * sq-new-plan. Changing a stage's days (dragging the edge of its box, or typing) changes that stage only and pushes
 * the rest, and the due date field becomes the end of the plan. Changing the due date field by hand makes the last
 * stage end on it. The start is the start date field (today when there is none). The date calculation is SqDates,
 * the same rules as the server (CreationPlan).
 * Redmine rebuilds the form for a new tracker or project and loads this script again: the second time it only lays
 * out the new bar.
 */
(function () {
  'use strict';

  if (window.SqNewPlan) { window.SqNewPlan.init(); return; }

  var STAGE_DAY_PX = 10; // each day after the first adds this much to a stage box (as on the issue page)
  var D = window.SqDates;

  function $(id) { return document.getElementById(id); }
  function each(list, fn) { Array.prototype.forEach.call(list, fn); }
  function root() { var r = $('sq-stage-timeline'); return r && r.classList.contains('sq-new-plan') ? r : null; }
  function segs() { var r = root(); return r ? r.querySelectorAll('.stage-drag-seg') : []; }
  function field(id) { var f = $(id); return f && !f.disabled && !f.readOnly ? f : null; }

  function calc() {
    var off = [];
    try { off = JSON.parse(root().getAttribute('data-non-working') || '[]'); } catch (e) { off = []; }
    return D.make(off);
  }

  function intOf(value, fallback) {
    var v = parseInt(value, 10);
    return (isNaN(v) || v < 1) ? fallback : Math.min(v, 365);
  }

  function stages() {
    return Array.prototype.map.call(segs(), function (seg) {
      return { id: seg.getAttribute('data-step'), seg: seg, input: seg.querySelector('.stage-duration-input'),
               all: seg.querySelector('.stage-all-days').checked };
    });
  }

  function startDay(c) {
    var f = $('issue_start_date');
    var value = f && f.value ? f.value : root().getAttribute('data-today');
    return c.next(D.dayNumber(value));
  }

  // ---- the width of each box: its own no-wrap width + STAGE_DAY_PX x (days - 1) -------------------

  function measureBases() {
    var list = segs();
    each(list, function (seg) { seg.style.width = 'max-content'; });
    var widths = Array.prototype.map.call(list, function (seg) { return Math.ceil(seg.getBoundingClientRect().width); });
    each(list, function (seg, i) { seg.setAttribute('data-base-px', widths[i]); });
  }

  function sizeSegs() {
    stages().forEach(function (st) {
      var base = parseInt(st.seg.getAttribute('data-base-px'), 10);
      if (!isNaN(base)) st.seg.style.width = (base + STAGE_DAY_PX * (intOf(st.input.value, 1) - 1)) + 'px';
    });
  }

  // ---- the plan --------------------------------------------------------------------------------------------

  // Lays the stages out and shows the dates; with fillDue, the due date field becomes the end of the plan
  function recalc(fillDue, fits) {
    if (!root()) return;
    var c = calc();
    var list = stages();
    var days = {};
    list.forEach(function (st) { days[st.id] = intOf(st.input.value, 1); });
    var plan = c.layout(list, startDay(c), days);
    var r = root();
    var startPill = r.querySelector('#stage-start-pill .stage-start-date');
    if (startPill && plan.length) startPill.textContent = D.mmdd(plan[0].start);
    plan.forEach(function (p, i) {
      var seg = list[i].seg;
      var pill = seg.querySelector('.sqb-pill-boundary .stage-plan-date');
      if (pill) pill.textContent = D.mmdd(p.end);
      seg.querySelector('.stage-days-unit').textContent = r.getAttribute(list[i].all ? 'data-t-all-days' : 'data-t-working') ||
        seg.querySelector('.stage-days-unit').textContent;
    });
    var end = plan.length ? plan[plan.length - 1].end : null;
    if (end !== null) {
      var total = $('preview-total-due-date');
      if (total) total.textContent = D.slashed(end);
      var duePill = r.querySelector('#stage-due-pill .stage-due-date');
      if (duePill) duePill.textContent = D.mmdd(end);
      var due = field('issue_due_date');
      if (fillDue && due) due.value = D.ymd(end);
    }
    var ok = fits !== false;
    var why = $('stage-cannot-fit');
    if (why) why.hidden = ok;
    var total2 = $('preview-total-due-date');
    if (total2) total2.style.color = ok ? '' : '#dc2626';
    sizeSegs();
  }

  // The due date field changed by hand: the last stage ends on it ("due date first", as after the creation)
  function dueChanged() {
    var due = field('issue_due_date');
    var list = stages();
    if (!due || !due.value || !list.length) { recalc(false); return; }
    var c = calc();
    var days = {};
    list.forEach(function (st) { days[st.id] = intOf(st.input.value, 1); });
    var slack = list[list.length - 1];
    var r = c.slackDays(list.slice(0, -1), slack, startDay(c), days, D.dayNumber(due.value));
    slack.input.value = r.days;
    recalc(false, r.fits);
  }

  // ---- the listeners -----------------------------------------------------------------------------------------

  function inBar(el) { return !!(el && el.closest && root() && root().contains(el)); }

  document.addEventListener('input', function (e) {
    if (inBar(e.target) && e.target.matches('.stage-duration-input')) recalc(true);
  });

  document.addEventListener('change', function (e) {
    var t = e.target;
    if (!t || !t.matches) return;
    if (inBar(t) && (t.matches('.stage-all-days') || t.matches('.stage-duration-input'))) {
      if (t.matches('.stage-duration-input')) t.value = intOf(t.value, 1);
      recalc(true);
    } else if (root() && t.id === 'issue_start_date') {
      recalc(true);
    } else if (root() && t.id === 'issue_due_date') {
      dueChanged();
    }
  });

  // Enter in a day box recalculates; it does not send the issue form
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && inBar(e.target) && e.target.matches('.stage-duration-input')) {
      e.preventDefault();
      e.target.value = intOf(e.target.value, 1);
      recalc(true);
    }
  });

  var dragging = null; // { input, startX, startDays, lastDays }

  document.addEventListener('pointerdown', function (e) {
    var handle = e.target.closest && e.target.closest('.stage-drag-handle');
    if (!handle || !inBar(handle)) return;
    var input = handle.closest('.stage-drag-seg').querySelector('.stage-duration-input');
    var days = intOf(input.value, 1);
    dragging = { input: input, startX: e.clientX, startDays: days, lastDays: days };
    try { handle.setPointerCapture(e.pointerId); } catch (err) { /* a synthetic event */ }
    e.preventDefault();
  });

  document.addEventListener('pointermove', function (e) {
    if (!dragging) return;
    var days = intOf(dragging.startDays + Math.round((e.clientX - dragging.startX) / STAGE_DAY_PX), 1);
    if (days === dragging.lastDays) return; // nothing to redraw until a whole day changes
    dragging.lastDays = days;
    dragging.input.value = days;
    recalc(true);
  });

  document.addEventListener('pointerup', function () { dragging = null; });
  document.addEventListener('pointercancel', function () { dragging = null; });

  // ---- start-up (and again for a rebuilt form) ---------------------------------------------------------------

  function init() {
    var r = root();
    if (!r) return;
    measureBases();
    // A new form (also a copy): the due date field is the end of the standard plan. A rebuilt form keeps both as sent.
    recalc(r.getAttribute('data-fill-due') === '1');
  }

  init();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { if (root()) { measureBases(); sizeSegs(); } });
  window.SqNewPlan = { init: init, recalc: recalc };
})();
