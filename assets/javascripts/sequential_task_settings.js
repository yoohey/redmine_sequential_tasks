/*
 * Sequential Tasks: the tracker settings (Administration > Sequential tasks settings). Moved out of the pages so a
 * strict Content Security Policy does not block it: the list's on/off switches, and the edit page (use, order by
 * dragging, color swatches, the preview of the bars, and asking before leaving with unsaved changes).
 */
(function () {
  'use strict';

  // ---- the list: the on/off switch saves at once; switching off asks first
  document.addEventListener('change', function (e) {
    var box = e.target.closest && e.target.closest('.sq-enable-form input[type=checkbox]');
    if (!box) return;
    var ask = box.getAttribute('data-confirm');
    if (ask && !box.checked && !window.confirm(ask)) { box.checked = true; return; }
    box.form.submit();
  });

  var tbody = document.getElementById('steps-tbody');
  if (!tbody) return;
  var form = document.getElementById('sequential-task-setting-form');

  // ---- asking before leaving with unsaved changes (saving clears it)
  var dirty = false;
  form.addEventListener('input', function () { dirty = true; });
  form.addEventListener('change', function () { dirty = true; });
  form.addEventListener('submit', function () { dirty = false; });
  window.addEventListener('beforeunload', function (e) {
    if (!dirty) return;
    e.preventDefault();
    e.returnValue = '';
  });

  // ---- use: a stage that is not used has its other inputs off
  tbody.addEventListener('change', function (e) {
    if (!e.target.classList.contains('sq-use')) return;
    var row = e.target.closest('tr');
    row.classList.toggle('sq-off', !e.target.checked);
    row.querySelectorAll('input:not(.sq-use), button').forEach(function (el) { el.disabled = !e.target.checked; });
  });

  // ---- order: drag the rows by the handle
  var dragged = null;
  tbody.addEventListener('mousedown', function (e) {
    var row = e.target.closest('tr');
    if (row) row.draggable = !!e.target.closest('.sq-handle');
  });
  tbody.addEventListener('dragstart', function (e) {
    dragged = e.target.closest('tr');
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', ''); // Firefox starts no drag without data
  });
  tbody.addEventListener('mouseup', function () {
    tbody.querySelectorAll('tr[draggable=true]').forEach(function (r) { r.draggable = false; });
  });
  tbody.addEventListener('dragover', function (e) {
    var row = e.target.closest('tr');
    if (!dragged || !row || row === dragged) return;
    e.preventDefault();
    var after = e.clientY > row.getBoundingClientRect().top + row.offsetHeight / 2;
    tbody.insertBefore(dragged, after ? row.nextSibling : row);
  });
  tbody.addEventListener('dragend', function () {
    if (dragged) dragged.draggable = false;
    dragged = null;
    dirty = true;
  });

  // ---- colors: a swatch sets the color; the color picker marks the swatch of the same color, if there is one
  function markSwatch(cell) {
    var value = cell.querySelector('input[type=color]').value.toLowerCase();
    cell.querySelectorAll('.sq-swatch').forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-color').toLowerCase() === value ? 'true' : 'false');
    });
  }
  tbody.addEventListener('click', function (e) {
    var sw = e.target.closest('.sq-swatch');
    if (!sw) return;
    var cell = sw.closest('td');
    cell.querySelector('input[type=color]').value = sw.getAttribute('data-color');
    markSwatch(cell);
    dirty = true;
    renderPreview();
  });
  tbody.addEventListener('input', function (e) {
    if (e.target.matches('input[type=color]')) markSwatch(e.target.closest('td'));
  });
  // the swatch colors come from data-color (no inline styles in the page), then each row marks its color
  tbody.querySelectorAll('.sq-swatch').forEach(function (b) { b.style.setProperty('--c', b.getAttribute('data-color')); });
  tbody.querySelectorAll('td.sq-col-color').forEach(markSwatch);

  // ---- the preview: the used stages as bars of the timeline (the real classes): done, current, then planned
  var styleInput = document.getElementById('bar_style');
  var previewStyle = styleInput.value;
  function renderPreview() {
    var box = document.getElementById('sq-preview');
    box.className = 'sq-style-' + previewStyle; // the styles are scoped to #sq-root .sq-style-*
    box.textContent = '';
    document.querySelectorAll('#sq-preview-style button').forEach(function (b) {
      b.setAttribute('aria-pressed', b.getAttribute('data-style') === previewStyle ? 'true' : 'false');
    });
    var rows = Array.prototype.filter.call(tbody.querySelectorAll('tr'), function (r) { return r.querySelector('.sq-use').checked; });
    if (!rows.length) {
      var em = document.createElement('em');
      em.textContent = box.getAttribute('data-empty');
      box.appendChild(em);
      return;
    }
    rows.forEach(function (row, i) {
      var label = row.querySelector('.sq-status-name').textContent.trim();
      var bar = document.createElement('div');
      bar.className = 'sq-bar sq-bar-' + (i === 0 ? 'done' : i === 1 ? 'cur' : 'future');
      bar.style.setProperty('--c', row.querySelector('input[type=color]').value);
      bar.title = label + ' ' + box.getAttribute('data-days').replace('__N__', row.querySelector('input[type=number]').value);
      bar.textContent = label;
      box.appendChild(bar);
    });
  }
  document.getElementById('sq-preview-style').addEventListener('click', function (e) {
    var b = e.target.closest('button');
    if (!b) return;
    previewStyle = b.getAttribute('data-style');
    styleInput.value = previewStyle; // saved with the form
    dirty = true;
    renderPreview();
  });
  tbody.addEventListener('input', renderPreview);
  tbody.addEventListener('change', renderPreview);
  tbody.addEventListener('dragend', renderPreview);
  renderPreview();
})();
