/*
 * Sequential Tasks: behavior of the project screens (timeline and matrix).
 * Loaded as a cacheable file; the page gives it its settings through data attributes
 * (#sq-root: branch URL, back URL, reorder URL and texts; #sq-lightning: slots of the lightning line).
 * Structure: helpers, then one section per feature, then the delegated listeners and the start-up at the end.
 * Speed notes:
 *  - clicks and changes are handled by delegated listeners instead of an inline handler per row, bar or control;
 *  - the lightning line reads all row positions first and then writes once; its points are drawn by an
 *    SVG marker on the polyline, so no DOM node is created per row; renders are coalesced per frame;
 *  - the inline "create a branched task" row is built on demand from one template.
 */
(function () {
  'use strict';

  var pending = false;
  var resizeTimer = null;
  var config = null;

  function each(list, fn) { Array.prototype.forEach.call(list, fn); }

  // ---- the area above the table stays put ----------------------------------------------------

  var MIN_SCROLLER_HEIGHT = 240; // in a very low window the page scrolls as usual

  // The tasks scroll inside .sq-scroller; its maximum height is what the window leaves, so the page itself
  // does not scroll and the Redmine header, the toolbar and the title stay in view, and the table runs down to
  // the footer. How: take the limit off, then the page is as tall as its content (the footer follows the
  // content); the part by which it is taller than the window is cut from the container. Measuring without
  // the limit matters: with a limit in place and a footer pinned to the bottom of a tall window, the empty
  // space would look like footer and the container could never grow again. A table that fits keeps its own
  // height. The height of the table header is handed to the group headers (they stick right under it).
  function fitScrollers() {
    var scrollers = document.querySelectorAll('.sq-scroller');
    var rootEl = document.getElementById('sq-root');
    // the inline view (inside the issue page) is as tall as its content: nothing to fit
    var fullView = rootEl && (rootEl.classList.contains('sq-full') || rootEl.classList.contains('sq-inline'));
    for (var i = 0; i < scrollers.length; i++) {
      var el = scrollers[i];
      // taking the limit off makes the container as tall as its content, which sets the scroll position back to the
      // top: it is put back at the end
      var keepTop = el.scrollTop;
      var keepLeft = el.scrollLeft;
      el.style.maxHeight = 'none';
      if (fullView) { // the full view has no scroll frame: nothing to fit (the stylesheet lifts the limits)
        var fullHead = el.querySelector('thead');
        if (fullHead) el.style.setProperty('--sq-head-h', fullHead.offsetHeight + 'px');
        continue;
      }
      var natural = el.offsetHeight;
      var overflow = document.documentElement.scrollHeight - window.innerHeight;
      if (overflow > 0) {
        el.style.maxHeight = Math.max(MIN_SCROLLER_HEIGHT, natural - overflow - 1) + 'px';
      }
      var head = el.querySelector('thead');
      if (head) el.style.setProperty('--sq-head-h', head.offsetHeight + 'px');
      el.scrollTop = keepTop;
      el.scrollLeft = keepLeft;
    }
  }

  window.fitSequentialTaskScrollers = fitScrollers; // (for measurements and tests)

  // ---- lightning line -------------------------------------------------------------------------

  function dayNumber(str) {
    var p = str.split('-');
    return Date.UTC(+p[0], +p[1] - 1, +p[2]) / 86400000;
  }

  function readConfig() {
    var source = document.getElementById('sq-lightning');
    if (!source) return null;
    var c = JSON.parse(source.textContent);
    c.left = c.state; // plus the width of the issue column, added at each render
    c.starts = c.slots.map(function (s) { return dayNumber(s[0]); });
    c.lengths = c.slots.map(function (s) { return dayNumber(s[1]) - dayNumber(s[0]) + 1; });
    return c;
  }

  // x position of a date: inside its slot in proportion to the day, left of the grid before it, at the end after it
  // edge: the left edge of the day instead of its middle (a wait before somebody picks the issue up: the point sits at the
  // left end of the bar that follows)
  function xForDate(c, str, edge) {
    if (!str) return c.left;
    var d = dayNumber(str);
    var lo = 0, hi = c.starts.length - 1, idx = -1;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (c.starts[mid] <= d) { idx = mid; lo = mid + 1; } else { hi = mid - 1; }
    }
    if (idx === -1) return c.left;
    if (d > c.starts[idx] + c.lengths[idx] - 1) return c.left + c.starts.length * c.slotWidth;
    var ratio = Math.max(0, Math.min(1, (d - c.starts[idx] + (edge ? 0 : 0.5)) / c.lengths[idx]));
    return c.left + idx * c.slotWidth + ratio * c.slotWidth;
  }

  function renderLightning() {
    var table = document.getElementById('timeline-table');
    var svg = document.getElementById('lightning-svg');
    if (!table || !svg) return;
    if (!config) config = readConfig();
    if (!config) return;
    var issueHead = table.querySelector('th.sq-th-issue');
    config.left = (issueHead ? issueHead.offsetWidth : 280) + config.state;

    var cache = {};
    var todayX = xForDate(config, config.today);
    var tableTop = table.getBoundingClientRect().top;
    var totalHeight = table.offsetHeight;
    var rows = table.querySelectorAll('tr.issue-row');

    // read phase: nothing is written to the page until all positions are known
    var headerHeight = table.tHead ? table.tHead.offsetHeight : 0; // the date header has several tiers
    var points = [todayX + ',' + headerHeight];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (row.style.display === 'none' || row.classList.contains('sq-folded')) continue;
      var rect = row.getBoundingClientRect();
      var date = row.getAttribute('data-progress-date');
      var edge = row.hasAttribute('data-edge');
      var key = edge ? date + 'e' : date;
      var x = cache[key];
      if (x === undefined) x = cache[key] = xForDate(config, date, edge);
      points.push(x + ',' + ((rect.top - tableTop) + rect.height / 2));
    }
    points.push(todayX + ',' + totalHeight);

    // write phase
    var todayLine = document.getElementById('today-vertical-line');
    if (todayLine) {
      todayLine.setAttribute('x1', todayX);
      todayLine.setAttribute('y1', 0);
      todayLine.setAttribute('x2', todayX);
      todayLine.setAttribute('y2', totalHeight);
    }
    var polyline = document.getElementById('lightning-polyline');
    if (polyline) polyline.setAttribute('points', points.join(' '));
    renderMilestoneLines(table, headerHeight, totalHeight);
  }

  // Dotted lines from the points of the milestone row down through all rows, when the switch is on. The position
  // of a point is its fraction over the dates (data-f), the same as the percentage that places it in the header.
  function renderMilestoneLines(table, headerHeight, totalHeight) {
    var group = document.getElementById('sq-ms-lines');
    if (!group) return;
    var markup = '';
    if (group.getAttribute('data-on') === '1') {
      each(table.querySelectorAll('a.sq-ms'), function (marker) {
        var x = config.left + parseFloat(marker.getAttribute('data-f')) * config.starts.length * config.slotWidth;
        var color = marker.classList.contains('sq-ms-closed') ? '#94a3b8' : (marker.classList.contains('sq-ms-issue') ? '#0891b2' : '#7c3aed');
        markup += '<line x1="' + x + '" x2="' + x + '" y1="' + headerHeight + '" y2="' + totalHeight +
                  '" stroke="' + color + '" stroke-width="1" stroke-dasharray="2,4" opacity="0.7"/>';
      });
    }
    group.innerHTML = markup;
  }

  // several triggers (load, resize, row changes) become one render per frame; a short timer backs up
  // requestAnimationFrame, which does not fire while a page is not being painted
  function scheduleLightning() {
    if (pending) return;
    pending = true;
    var run = function () {
      if (!pending) return;
      pending = false;
      renderLightning();
    };
    window.requestAnimationFrame(run);
    setTimeout(run, 100);
  }

  window.renderLightningLine = scheduleLightning;
  window.renderLightningLineNow = renderLightning; // synchronous (for measurements and tests)

  function toggleLightningLine(checkbox) {
    var svg = document.getElementById('lightning-svg');
    if (svg) svg.style.display = checkbox.checked ? 'block' : 'none';
    // the red subjects of delayed issues belong to the lightning line: they go with it
    var root = document.getElementById('sq-root');
    if (root) root.classList.toggle('sq-lightning-on', checkbox.checked);
  }

  // ---- groups ---------------------------------------------------------------------------------

  function setGroup(gIdx, expand) {
    var rows = document.querySelectorAll('.issue-row.group-child-' + gIdx);
    each(rows, function (r) { r.style.display = expand ? '' : 'none'; });
    if (!expand) removeBranchRows('.group-branch-' + gIdx);
    var icon = document.getElementById('group-icon-' + gIdx);
    if (icon) icon.textContent = expand ? '▼' : '▶';
  }

  function toggleGroupCollapse(gIdx) {
    var rows = document.querySelectorAll('.issue-row.group-child-' + gIdx);
    if (rows.length === 0) return;
    setGroup(gIdx, rows[0].style.display === 'none');
    scheduleLightning();
  }

  function toggleAllGroups(expand) {
    each(document.querySelectorAll('[id^="group-icon-"]'), function (icon) {
      setGroup(icon.id.replace('group-icon-', ''), expand);
    });
    scheduleLightning();
  }

  // ---- rows and their branches ----------------------------------------------------------------
  // Every row carries data-id and data-p (the parent issue, empty at the top level); a row's branches follow it.

  // the class that tells which group a row is in ('' when not grouped)
  function groupKey(tr) {
    var found = Array.prototype.filter.call(tr.classList, function (c) { return c.indexOf('group-child-') === 0; })[0];
    return found || '';
  }

  function rowById(id) { return document.querySelector('tr.issue-row[data-id="' + id + '"]'); }

  // the rows of the branches (and their branches) that follow the row
  function descendantsOf(tr) {
    var ids = {};
    ids[tr.getAttribute('data-id')] = true;
    var rows = [];
    var next = tr.nextElementSibling;
    while (next) {
      if (next.classList.contains('sq-branch-row')) { next = next.nextElementSibling; continue; }
      if (!next.hasAttribute('data-id') || !ids[next.getAttribute('data-p')]) break;
      ids[next.getAttribute('data-id')] = true;
      rows.push(next);
      next = next.nextElementSibling;
    }
    return rows;
  }

  // ---- inline "create a branched task" row ----------------------------------------------------

  function removeBranchRows(selector) {
    each(document.querySelectorAll(selector), function (r) { r.parentNode.removeChild(r); });
  }

  function hiddenInput(name, value) {
    var input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    return input;
  }

  var branchFormSeq = 0;

  function toggleBranchRow(link) {
    var root = document.getElementById('sq-root');
    var template = document.getElementById('sq-branch-template');
    var tr = link.closest('tr');
    if (!root || !template || !tr) return;

    var next = tr.nextElementSibling;
    if (next && next.classList.contains('sq-branch-row')) {
      next.parentNode.removeChild(next);
      scheduleLightning();
      return;
    }

    var subjectLink = tr.querySelector('a.sq-subj');
    var idMatch = subjectLink && subjectLink.getAttribute('href').match(/\/issues\/(\d+)/);
    if (!idMatch) return;
    var subject = subjectLink.textContent.trim().replace(/^#\d+\s+/, '');
    var number = parseInt(tr.getAttribute('data-bc') || '0', 10) + 1;
    var assigneeEl = tr.querySelector('.sq-asg');
    var assignee = (assigneeEl && !assigneeEl.classList.contains('sq-none')) ? assigneeEl.textContent.trim()
                                                                             : template.getAttribute('data-unassigned');

    var fragment = template.content.cloneNode(true);
    var form = fragment.querySelector('form');
    form.action = root.getAttribute('data-branch-url').replace('__ID__', idMatch[1]);
    form.appendChild(hiddenInput('back_url', root.getAttribute('data-back-url')));
    var meta = document.querySelector('meta[name="csrf-token"]');
    if (meta) form.appendChild(hiddenInput('authenticity_token', meta.getAttribute('content')));
    var input = form.querySelector('input[name="subject"]');
    input.value = subject + '_' + number;
    var note = fragment.querySelector('.sq-note');
    // the start date the branch will get: the parent's when it starts later than today (data-bs), else today
    var startDate = tr.getAttribute('data-bs') || template.getAttribute('data-today');
    note.textContent = template.getAttribute('data-note').replace('@@A@@', assignee).replace('@@D@@', startDate);

    var columns = Array.prototype.reduce.call(tr.cells, function (n, c) { return n + c.colSpan; }, 0);
    var row = document.createElement('tr');
    row.className = 'sq-branch-row';
    if (groupKey(tr)) row.classList.add(groupKey(tr).replace('group-child-', 'group-branch-'));
    // the input sits under the issue column, the buttons under the state column (they belong to the form
    // through the form attribute)
    var formId = 'sq-bf-' + (++branchFormSeq);
    form.id = formId;
    var submitButton = form.querySelector('button[type="submit"]');
    var cancelButton = form.querySelector('[data-act="branch-cancel"]');
    submitButton.setAttribute('form', formId);
    form.addEventListener('submit', function () { submitButton.disabled = true; }); // once: no second issue from a double click
    var left = row.insertCell();
    left.className = 'sq-sticky sq-c-branch';
    left.appendChild(form);
    var middle = row.insertCell();
    middle.className = 'sq-sticky sq-c-branch-state';
    middle.appendChild(submitButton);
    middle.appendChild(cancelButton);
    var right = row.insertCell();
    right.colSpan = Math.max(columns - 2, 1);
    right.className = 'sq-branch-note';
    right.appendChild(note);
    tr.parentNode.insertBefore(row, tr.nextSibling);
    input.focus();
    input.select();
    scheduleLightning();
  }

  // ---- reorder mode ---------------------------------------------
  // The handle is in every row when the user may reorder in the manual order, but hidden by CSS (it takes the
  // place of the +branch button) until the mode is on. The mode lives only in this page: it is off at every load and when the page is shown again from the
  // back/forward cache. Moving is optimistic (the DOM changes at once); a failed save reloads the page.

  var dragged = null;
  var saveQueue = Promise.resolve();

  function reorderRoot() {
    var root = document.getElementById('sq-root');
    return root && root.getAttribute('data-reorder-url') ? root : null;
  }

  function setReorderMode(on) {
    var root = reorderRoot();
    each(document.querySelectorAll('.sq-mode-btn'), function (box) {
      box.setAttribute('aria-pressed', on ? 'true' : 'false');
      box.classList.toggle('sq-on', on);
    });
    if (!root) return;
    root.classList.toggle('sq-reorder', on);
    if (on) {
      var text = root.getAttribute('data-t-drag');
      each(root.querySelectorAll('.sq-hd'), function (el) { el.title = text; });
    }
  }

  function visible(tr) { return tr.style.display !== 'none' && !tr.classList.contains('sq-folded'); }

  // the rows that share this row's parent, in the same table and group, in screen order
  function siblingsOf(tr) {
    var table = tr.closest('table');
    var parent = tr.getAttribute('data-p');
    var key = groupKey(tr);
    return Array.prototype.filter.call(table.querySelectorAll('tr.issue-row[data-id]'), function (r) {
      return r.getAttribute('data-p') === parent && groupKey(r) === key && visible(r);
    });
  }

  // the row and its branches (a tree is kept together)
  function blockOf(tr) { return [tr].concat(descendantsOf(tr)); }

  // PUT a form body with the CSRF token; resolves to the fetch response
  function sendPut(url, body) {
    var meta = document.querySelector('meta[name="csrf-token"]');
    var headers = { 'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'XMLHttpRequest' };
    if (meta) headers['X-CSRF-Token'] = meta.getAttribute('content');
    return fetch(url, { method: 'PUT', headers: headers, body: body, credentials: 'same-origin' });
  }

  function saveOrder(url, issueId, beforeId) {
    var body = 'issue_id=' + encodeURIComponent(issueId) + (beforeId ? '&before_id=' + encodeURIComponent(beforeId) : '');
    saveQueue = saveQueue.then(function () {
      return sendPut(url, body);
    }).then(function (res) {
      if (!res.ok) throw new Error(res.status);
    }).catch(function () {
      var root = reorderRoot();
      window.alert(root ? root.getAttribute('data-t-failed') : 'Failed');
      window.location.reload();
    });
  }

  // Puts the row (with its branches) right before beforeRow; with no beforeRow, after the last sibling.
  function moveRow(tr, beforeRow) {
    var root = reorderRoot();
    if (!root || beforeRow === tr) return;
    var sibs = siblingsOf(tr);
    var anchor;
    if (beforeRow) {
      anchor = beforeRow;
    } else {
      var last = sibs[sibs.length - 1];
      if (last === tr) return;
      var lastBlock = blockOf(last);
      anchor = lastBlock[lastBlock.length - 1].nextElementSibling;
    }
    var block = blockOf(tr);
    if (anchor === block[block.length - 1].nextElementSibling) return; // already there
    removeBranchRows('.sq-branch-row');
    var parent = tr.parentNode;
    var fragment = document.createDocumentFragment();
    block.forEach(function (r) { fragment.appendChild(r); });
    parent.insertBefore(fragment, anchor); // a null anchor appends
    scheduleLightning();
    saveOrder(root.getAttribute('data-reorder-url'), tr.getAttribute('data-id'), beforeRow ? beforeRow.getAttribute('data-id') : '');
  }

  function clearDropMarks() {
    each(document.querySelectorAll('tr.sq-drop-before, tr.sq-drop-after, tr.sq-drop-group'), function (r) {
      r.classList.remove('sq-drop-before', 'sq-drop-after', 'sq-drop-group');
    });
  }

  // ---- moving an issue to another version ------------------------------------------
  // With the version grouping and the reorder mode, dropping a row on another group (its header or one of its rows)
  // changes the issue's target version. The row moves when the server has accepted the change; the release marks
  // of the moved row are removed (they would be out of date until the page is opened again).

  function groupIndex(tr) { return groupKey(tr).replace('group-child-', ''); }

  // the index of the other group under the pointer, or null
  function versionTarget(event) {
    var root = document.getElementById('sq-root');
    if (!dragged || !root || !root.getAttribute('data-version-url') || !event.target.closest) return null;
    var tr = event.target.closest('tr.issue-row[data-id], tr.group-header-row');
    if (!tr) return null;
    var index = tr.classList.contains('group-header-row') ? tr.getAttribute('data-group') : groupIndex(tr);
    return index && index !== groupIndex(dragged) ? index : null;
  }

  function groupHeader(index) { return document.querySelector('tr.group-header-row[data-group="' + index + '"]'); }

  // "(17)" and the number of late ones in the header of a group follow the rows
  function refreshGroupCounts(index) {
    var header = groupHeader(index);
    if (!header) return;
    var rows = document.querySelectorAll('tr.issue-row.group-child-' + index);
    var count = header.querySelector('.sq-gh-count');
    if (count) count.textContent = count.textContent.replace(/\d+/, rows.length);
    var risk = header.querySelector('.sq-gh-risk');
    if (risk) {
      var late = 0;
      each(rows, function (r) { if (r.querySelector('.sq-rl')) late++; });
      risk.textContent = '⏱ ' + late;
      risk.style.display = late ? '' : 'none';
    }
  }

  function applyGroupMove(tr, index) {
    if (descendantsOf(tr).length > 0) { window.location.reload(); return; } // its branches would be left behind
    var from = groupIndex(tr);
    var rows = document.querySelectorAll('tr.issue-row.group-child-' + index);
    var last = rows[rows.length - 1];
    var lastBlock = blockOf(last);
    var anchor = lastBlock[lastBlock.length - 1].nextElementSibling;
    tr.classList.remove('group-child-' + from);
    tr.classList.add('group-child-' + index);
    tr.style.display = last.style.display; // a folded group stays folded
    each(tr.querySelectorAll('i.sq-rel, .sq-rl'), function (el) { el.parentNode.removeChild(el); });
    last.parentNode.insertBefore(tr, anchor);
    refreshGroupCounts(from);
    refreshGroupCounts(index);
    tr.classList.add('sq-moved');
    setTimeout(function () { tr.classList.remove('sq-moved'); }, 1500);
    scheduleLightning();
  }

  function moveToGroup(tr, index) {
    var root = document.getElementById('sq-root');
    var version = groupHeader(index).getAttribute('data-version');
    var body = 'issue_id=' + encodeURIComponent(tr.getAttribute('data-id')) + '&version_id=' + (version === 'none' ? '' : encodeURIComponent(version));
    var failed = function (text) { window.alert(text || root.getAttribute('data-t-version-failed')); };
    sendPut(root.getAttribute('data-version-url'), body).then(function (res) {
      if (res.ok) { applyGroupMove(tr, index); return null; }
      return res.text().then(failed);
    }).catch(function () { failed(''); });
  }

  // the sibling row under the pointer and whether the pointer is in its upper half; null when not a valid place
  function dropTarget(event) {
    if (!dragged || !event.target.closest) return null;
    var tr = event.target.closest('tr.issue-row[data-id]');
    if (!tr || tr === dragged || siblingsOf(dragged).indexOf(tr) < 0) return null;
    var rect = tr.getBoundingClientRect();
    return { row: tr, upper: event.clientY < rect.top + rect.height / 2 };
  }

  document.addEventListener('dragstart', function (event) {
    var handle = event.target.closest && event.target.closest('#sq-root.sq-reorder .sq-hd');
    if (!handle) return;
    dragged = handle.closest('tr');
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', dragged.getAttribute('data-id')); // Firefox needs data to start a drag
    event.dataTransfer.setDragImage(dragged, 10, 10);
    blockOf(dragged).forEach(function (r) { r.classList.add('sq-dragging'); });
  });

  document.addEventListener('dragover', function (event) {
    var target = dropTarget(event);
    clearDropMarks();
    if (!target) {
      var other = versionTarget(event);
      if (other !== null) {
        event.preventDefault();
        groupHeader(other).classList.add('sq-drop-group');
      }
      return;
    }
    event.preventDefault();
    target.row.classList.add(target.upper ? 'sq-drop-before' : 'sq-drop-after');
  });

  document.addEventListener('drop', function (event) {
    var target = dropTarget(event);
    if (!target) {
      var other = versionTarget(event);
      if (other !== null) {
        event.preventDefault();
        clearDropMarks();
        moveToGroup(dragged, other);
      }
      return;
    }
    event.preventDefault();
    var tr = dragged;
    var beforeRow = target.row;
    if (!target.upper) {
      var sibs = siblingsOf(tr);
      var next = sibs[sibs.indexOf(target.row) + 1];
      beforeRow = next || null;
      if (next === tr) beforeRow = sibs[sibs.indexOf(tr) + 1] || null; // dropped just below its own place
    }
    clearDropMarks();
    moveRow(tr, beforeRow);
  });

  document.addEventListener('dragend', function () {
    clearDropMarks();
    each(document.querySelectorAll('tr.sq-dragging'), function (r) { r.classList.remove('sq-dragging'); });
    dragged = null;
  });

  // ---- the width of the issue column ----------------------------------------------------------
  // Dragging the right edge of the "Issue / Assignee" header sets --sq-issue-w on #sq-root; every column
  // that depends on it (sticky offset, table width) follows through CSS. The width is remembered per
  // browser (a convenience; the page works without storage).

  // (the inline view inside an issue page is narrow and has its own width: it may be narrower)
  var INLINE = !!(document.getElementById('sq-root') && document.getElementById('sq-root').classList.contains('sq-inline'));
  var MIN_ISSUE_W = INLINE ? 120 : 200, MAX_ISSUE_W = 700, WIDTH_KEY = INLINE ? 'sqIssueColumnWidthInline' : 'sqIssueColumnWidth';

  function setIssueWidth(px) {
    var root = document.getElementById('sq-root');
    if (root) root.style.setProperty('--sq-issue-w', Math.max(MIN_ISSUE_W, Math.min(MAX_ISSUE_W, Math.round(px))) + 'px');
  }

  function restoreIssueWidth() {
    try {
      var saved = parseInt(window.localStorage.getItem(WIDTH_KEY), 10);
      if (saved) setIssueWidth(saved);
    } catch (e) { /* no storage: the default width stays */ }
  }

  document.addEventListener('pointerdown', function (event) {
    var grip = event.target.closest && event.target.closest('#sq-root .sq-rz');
    if (!grip) return;
    event.preventDefault();
    var head = grip.parentNode;
    var startX = event.clientX;
    var startW = head.offsetWidth;
    grip.classList.add('sq-active');
    if (grip.setPointerCapture) grip.setPointerCapture(event.pointerId);
    var move = function (e) { setIssueWidth(startW + e.clientX - startX); scheduleLightning(); };
    var done = function () {
      grip.removeEventListener('pointermove', move);
      grip.removeEventListener('pointerup', done);
      grip.removeEventListener('pointercancel', done);
      grip.classList.remove('sq-active');
      try { window.localStorage.setItem(WIDTH_KEY, String(head.offsetWidth)); } catch (e) { /* ignore */ }
    };
    grip.addEventListener('pointermove', move);
    grip.addEventListener('pointerup', done);
    grip.addEventListener('pointercancel', done);
  });

  // ---- folding the branches of an issue -------------------------------------------------------
  // On load, a small button is added to every issue that has branches on the screen (no markup per row for the
  // others). Folding hides the rows below it with the class sq-folded, which is separate from the group
  // switches (style.display), so unfolding never shows a row another switch hides.

  function addFoldButtons() {
    var root = document.getElementById('sq-root');
    if (!root) return;
    var parents = {};
    var rows = root.querySelectorAll('tr.issue-row[data-p]');
    each(rows, function (r) { if (r.getAttribute('data-p')) parents[r.getAttribute('data-p')] = true; });
    var title = root.getAttribute('data-t-fold') || '';
    each(root.querySelectorAll('tr.issue-row[data-id]'), function (r) {
      if (!parents[r.getAttribute('data-id')] || descendantsOf(r).length === 0) return;
      var ib = r.querySelector('.sq-ib');
      if (!ib) return;
      var button = document.createElement('button');
      button.type = 'button';
      button.className = 'sq-fold';
      button.title = title;
      button.textContent = '▼';
      ib.insertBefore(button, ib.querySelector('.sq-hd, a.sq-plus'));
    });
  }

  function toggleFold(button) {
    var tr = button.closest('tr');
    var collapsed = !tr.classList.contains('sq-collapsed');
    tr.classList.toggle('sq-collapsed', collapsed);
    var rows = descendantsOf(tr);
    var hidden = {};
    rows.forEach(function (r) {
      var parent = r.getAttribute('data-p');
      var parentRow = parent === tr.getAttribute('data-id') ? tr : rowById(parent);
      var hide = (parentRow && parentRow.classList.contains('sq-collapsed')) || hidden[parent];
      r.classList.toggle('sq-folded', !!hide);
      if (hide) hidden[r.getAttribute('data-id')] = true;
    });
    button.textContent = collapsed ? '▶ ' + rows.length : '▼';
    removeBranchRows('.sq-branch-row');
    scheduleLightning();
  }

  // all issues at once: collapse or expand every issue that has branches
  function foldAll(collapse) {
    each(document.querySelectorAll('#sq-root button.sq-fold'), function (button) {
      var isCollapsed = button.closest('tr').classList.contains('sq-collapsed');
      if (isCollapsed !== collapse) toggleFold(button);
    });
  }

  // On opening, today is in the middle of the visible dates (the issue and state columns stay at the left)
  function scrollToToday() {
    var scroller = document.getElementById('timeline-scroll-container');
    var head = document.querySelector('#timeline-table th.sq-th-issue');
    if (!scroller || !head) return;
    if (!config) config = readConfig();
    if (!config) return;
    var left = head.offsetWidth + config.state;
    var x = xForDate(Object.assign({}, config, { left: left }), config.today);
    scroller.scrollLeft = Math.max(0, x - left / 2 - scroller.clientWidth / 2);
  }

  // ---- the full view -------------------------------------------------------------------------------
  // With no scroll frame the tables keep their natural width, wider than the window. The page has to be as wide as the
  // widest table (plus the padding around it), or the part beyond the window cannot be reached or captured.

  function setFullWidth(on) {
    var root = document.documentElement;
    if (!on) { root.style.removeProperty('--sq-full-w'); return; }
    var widest = 0;
    each(document.querySelectorAll('#sq-root table'), function (t) { widest = Math.max(widest, t.getBoundingClientRect().width); });
    root.style.setProperty('--sq-full-w', Math.ceil(widest + 60) + 'px');
  }

  // ---- the panel for the issue -----------------------------------------
  // A click on a subject (or a bar) opens Redmine's own issue page in a panel on the right (an iframe; the hook of the
  // plugin hides Redmine's frame in it). When the issue is saved there (the page that comes back has a notice), the
  // screen is read again and replaces its content, with the scroll position and the switches kept.

  var panelUrl = '';
  var refreshing = false;
  var panelIssueId = null; // the issue shown in the panel: its rows are marked (also after a refresh)

  function markSelected() {
    each(document.querySelectorAll('#sq-root tr.sq-selected'), function (tr) { tr.classList.remove('sq-selected'); });
    var shown = panelIssueId || floatIssueId;
    if (shown) {
      each(document.querySelectorAll('#sq-root tr.sq-row[data-id="' + shown + '"]'), function (tr) { tr.classList.add('sq-selected'); });
    }
    updateStepButtons();
  }

  // The previous and next issue for the panel's buttons: in the order of the rows on the screen (its sorting, filters,
  // groups and folded branches), not Redmine's order by number, which the panel hides
  function visibleIssueRows() {
    var seen = {};
    return Array.prototype.filter.call(document.querySelectorAll('#sq-root tr.sq-row[data-id]'), function (tr) {
      var id = tr.getAttribute('data-id');
      if (seen[id] || !tr.querySelector('a.sq-subj') || tr.offsetParent === null) return false;
      seen[id] = true;
      return true;
    });
  }

  function stepRow(delta) {
    var rows = visibleIssueRows();
    var at = -1;
    var shown = panelIssueId || floatIssueId;
    for (var i = 0; i < rows.length; i++) { if (rows[i].getAttribute('data-id') === shown) { at = i; break; } }
    if (at < 0) return null;
    return rows[at + delta] || null;
  }

  function updateStepButtons() { // the panel's and the floating window's (whichever is open follows the shown issue)
    var up = !stepRow(-1), down = !stepRow(1);
    each(document.querySelectorAll('#sq-panel .sq-panel-prev, #sq-float .sq-panel-prev'), function (b) { b.disabled = up; });
    each(document.querySelectorAll('#sq-panel .sq-panel-next, #sq-float .sq-panel-next'), function (b) { b.disabled = down; });
  }

  function stepPanel(delta) {
    var row = stepRow(delta);
    if (!row) return;
    var link = row.querySelector('a.sq-subj');
    if (floatOpen()) openFloat(link.getAttribute('href'), link.textContent.trim());
    else openPanel(link);
    var scroller = row.closest('.sq-scroller');
    if (scroller) { // a row out of the scroll frame comes in just at its edge: one row of scrolling, up or down alike
      var head = scroller.querySelector('thead');
      var frame = scroller.getBoundingClientRect();
      var box = row.getBoundingClientRect();
      var top = frame.top + scroller.clientTop + (head ? head.offsetHeight : 0); // under the frozen header
      var bottom = frame.top + scroller.clientTop + scroller.clientHeight;        // above the horizontal scroll bar
      if (box.top < top) scroller.scrollTop -= top - box.top;
      else if (box.bottom > bottom) scroller.scrollTop += box.bottom - bottom;
    }
  }

  function issueIdOf(path) {
    var m = /\/issues\/(\d+)(\/|$|\?)/.exec(path || '');
    return m ? m[1] : null;
  }

  // The panel lives in <body>, outside the content that a refresh replaces; it is made once, from the template
  function ensurePanel() {
    var panel = document.getElementById('sq-panel');
    if (panel) return panel;
    var template = document.getElementById('sq-panel-template');
    if (!template) return null;
    document.body.appendChild(template.content.cloneNode(true));
    panel = document.getElementById('sq-panel');
    panel.querySelector('.sq-panel-close').addEventListener('click', closePanel);
    panel.querySelector('iframe').addEventListener('load', onPanelLoad);
    panel.querySelector('.sq-panel-dock').addEventListener('click', function () {
      setDock(panelDock() === 'bottom' ? 'right' : 'bottom');
    });
    panel.querySelector('.sq-panel-grip').addEventListener('pointerdown', startPanelResize);
    panel.querySelector('.sq-panel-prev').addEventListener('click', function () { stepPanel(-1); });
    panel.querySelector('.sq-panel-next').addEventListener('click', function () { stepPanel(1); });
    try {
      var savedHeight = parseInt(window.localStorage.getItem(PANEL_HEIGHT_KEY), 10);
      if (savedHeight) setPanelHeight(savedHeight);
    } catch (e) { /* no storage: the default height */ }
    applyDock(panel);
    return panel;
  }

  // Where the panel stands, right or bottom: the button in its head switches it, and the browser remembers it (a
  // convenience, like the width of the issue column). At the bottom, its top edge drags its height.
  var PANEL_DOCK_KEY = 'sqPanelDock', PANEL_HEIGHT_KEY = 'sqPanelHeight', MIN_PANEL_H = 150;
  var dockMemo = null;

  function panelDock() {
    if (dockMemo) return dockMemo;
    try { dockMemo = window.localStorage.getItem(PANEL_DOCK_KEY) === 'bottom' ? 'bottom' : 'right'; } catch (e) { dockMemo = 'right'; }
    return dockMemo;
  }

  function applyDock(panel) {
    var bottom = panelDock() === 'bottom';
    panel.classList.toggle('sq-panel-bottom', bottom);
    document.body.classList.toggle('sq-panel-at-bottom', bottom);
    var button = panel.querySelector('.sq-panel-dock');
    button.textContent = panel.getAttribute(bottom ? 'data-t-right' : 'data-t-bottom');
  }

  function setDock(dock) {
    dockMemo = dock;
    try { window.localStorage.setItem(PANEL_DOCK_KEY, dock); } catch (e) { /* this page only */ }
    var panel = document.getElementById('sq-panel');
    if (panel) applyDock(panel);
    relayout();
  }

  // The tallest the panel at the bottom may be: the table above it keeps its least height (MIN_SCROLLER_HEIGHT), so
  // that the page still fits the window and does not scroll (what stands above and below the table is measured)
  function maxPanelHeight() {
    var limit = window.innerHeight - MIN_PANEL_H;
    var scroller = document.querySelector('#sq-root .sq-scroller');
    var panel = document.getElementById('sq-panel');
    if (scroller && panel && !panel.hidden && panel.classList.contains('sq-panel-bottom')) {
      var top = scroller.getBoundingClientRect().top + window.scrollY;
      // below the table: the bottom padding of the content and Redmine's footer (not the page's own height, which
      // Redmine stretches to the window)
      var content = document.getElementById('content');
      var footer = document.getElementById('footer');
      var below = (content ? parseFloat(getComputedStyle(content).paddingBottom) || 0 : 0) + (footer ? footer.offsetHeight : 0) + 2;
      limit = Math.min(limit, window.innerHeight - (top + MIN_SCROLLER_HEIGHT + below));
    }
    return Math.max(MIN_PANEL_H, limit);
  }

  function setPanelHeight(px) {
    var h = Math.max(MIN_PANEL_H, Math.min(maxPanelHeight(), Math.round(px)));
    document.documentElement.style.setProperty('--sq-panel-h', h + 'px');
    return h;
  }

  // after the panel opens at the bottom or the window changes: a remembered height that no longer fits is cut down
  function fitPanelHeight() {
    var panel = document.getElementById('sq-panel');
    if (!panel || panel.hidden || !panel.classList.contains('sq-panel-bottom')) return;
    if (panel.offsetHeight > maxPanelHeight()) setPanelHeight(panel.offsetHeight);
  }

  function startPanelResize(event) {
    var grip = event.currentTarget;
    var panel = document.getElementById('sq-panel');
    event.preventDefault();
    var startY = event.clientY;
    var startH = panel.offsetHeight;
    var height = startH;
    grip.classList.add('sq-active');
    if (grip.setPointerCapture) grip.setPointerCapture(event.pointerId); // the iframe would swallow the moves otherwise
    var move = function (e) { height = setPanelHeight(startH - (e.clientY - startY)); };
    var done = function () {
      grip.removeEventListener('pointermove', move);
      grip.removeEventListener('pointerup', done);
      grip.removeEventListener('pointercancel', done);
      grip.classList.remove('sq-active');
      try { window.localStorage.setItem(PANEL_HEIGHT_KEY, String(height)); } catch (e) { /* ignore */ }
      relayout();
    };
    grip.addEventListener('pointermove', move);
    grip.addEventListener('pointerup', done);
    grip.addEventListener('pointercancel', done);
  }

  function relayout() { fitPanelHeight(); fitScrollers(); scheduleLightning(); } // the page got narrower or wider

  function isInline() { var r = document.getElementById('sq-root'); return !!(r && r.classList.contains('sq-inline')); }

  function openPanel(link) {
    if (isInline()) return false; // inside the issue page there is no side panel: links open in the page that holds the frame
    closeFloat(); // the panel or the floating window, one at a time
    var panel = ensurePanel();
    if (!panel) return false;
    var url = link.getAttribute('href');
    panel.querySelector('.sq-panel-title').textContent = link.textContent.trim();
    panel.querySelector('.sq-panel-open').setAttribute('href', url);
    if (panelUrl !== url) {
      panelUrl = url;
      // sq_embed=1 asks for the page without Redmine's frame (browsers send Sec-Fetch-Dest for what follows)
      panel.querySelector('iframe').src = url + (url.indexOf('?') < 0 ? '?' : '&') + 'sq_embed=1';
    }
    panel.hidden = false;
    document.body.classList.add('sq-panel-on');
    applyDock(panel);
    panelIssueId = issueIdOf(url);
    markSelected();
    relayout();
    return true;
  }

  function closePanel() {
    var panel = document.getElementById('sq-panel');
    if (!panel || panel.hidden) return;
    panel.hidden = true;
    document.body.classList.remove('sq-panel-on', 'sq-panel-at-bottom');
    panel.querySelector('iframe').src = 'about:blank';
    panelUrl = '';
    panelIssueId = null;
    markSelected();
    relayout();
  }

  // ---- the floating window -----------------------------------------
  // A small window over the screen with the head of an issue, its attributes and its stage timeline with the
  // adjusting (the issue page in a frame, sq_float=1 leaves the rest out). One at a time; its head drags it; the
  // browser remembers where it stood. A double click on a bar opens it (the panel shows the whole issue page, so it
  // has no button for it).
  var floatIssueId = null;
  var FLOAT_POS_KEY = 'sqFloatPos';

  function ensureFloat() {
    var win = document.getElementById('sq-float');
    if (win) return win;
    var template = document.getElementById('sq-float-template');
    if (!template) return null;
    document.body.appendChild(template.content.cloneNode(true));
    win = document.getElementById('sq-float');
    win.querySelector('.sq-float-close').addEventListener('click', closeFloat);
    win.querySelector('.sq-float-panel').addEventListener('click', function () {
      var a = win.querySelector('.sq-float-open');
      var fake = document.createElement('a');
      fake.setAttribute('href', a.getAttribute('href'));
      fake.textContent = win.querySelector('.sq-float-title').textContent;
      openPanel(fake);
    });
    win.querySelector('iframe').addEventListener('load', onFloatLoad);
    win.querySelector('.sq-panel-prev').addEventListener('click', function () { stepPanel(-1); });
    win.querySelector('.sq-panel-next').addEventListener('click', function () { stepPanel(1); });
    win.querySelector('.sq-float-head').addEventListener('pointerdown', startFloatDrag);
    var grip = win.querySelector('.sq-float-grip');
    grip.addEventListener('pointerdown', startFloatResize);
    grip.addEventListener('dblclick', function () { // back to the size that fits the issue
      try { window.localStorage.removeItem(FLOAT_SIZE_KEY); } catch (e) { /* ignore */ }
      win.style.width = '';
      try { fitFloatHeight(win.querySelector('iframe').contentDocument); } catch (e) { /* not loaded yet */ }
    });
    return win;
  }

  function placeFloat(win, left, top) {
    var maxLeft = Math.max(0, window.innerWidth - win.offsetWidth);
    var maxTop = Math.max(0, window.innerHeight - 40);
    win.style.left = Math.max(0, Math.min(maxLeft, Math.round(left))) + 'px';
    win.style.top = Math.max(0, Math.min(maxTop, Math.round(top))) + 'px';
  }

  function openFloat(url, title) {
    if (isInline() || !url) return false;
    var win = ensureFloat();
    if (!win) return false;
    closePanel(); // one at a time
    url = url.replace(/[?&]sq_(embed|float)=1/g, '');
    win.querySelector('.sq-float-title').textContent = title || '';
    win.querySelector('.sq-float-open').setAttribute('href', url);
    win.querySelector('iframe').src = url + (url.indexOf('?') < 0 ? '?' : '&') + 'sq_embed=1&sq_float=1';
    var first = win.hidden;
    win.hidden = false;
    var size = floatSize();
    if (first && size) setFloatSize(win, size.w, size.h);
    if (first) {
      var pos = null;
      try { pos = JSON.parse(window.localStorage.getItem(FLOAT_POS_KEY) || 'null'); } catch (e) { pos = null; }
      if (pos) placeFloat(win, pos.left, pos.top);
      else placeFloat(win, window.innerWidth - win.offsetWidth - 24, window.innerHeight - 420);
    }
    floatIssueId = issueIdOf(url);
    markSelected();
    return true;
  }

  function floatOpen() {
    var win = document.getElementById('sq-float');
    return !!(win && !win.hidden);
  }

  function closeFloat() {
    var win = document.getElementById('sq-float');
    if (!win || win.hidden) return;
    win.hidden = true;
    win.querySelector('iframe').src = 'about:blank';
    floatIssueId = null;
    markSelected();
  }

  // What the window loaded: its height follows the content; a saved issue (a notice) refreshes the screen; leaving
  // the issue closes the window
  function onFloatLoad(event) {
    var frame = event.target;
    var doc, path;
    try {
      if (frame.contentWindow.location.href === 'about:blank') return;
      doc = frame.contentDocument;
      path = frame.contentWindow.location.pathname;
    } catch (e) { return; }
    if (!doc) return;
    if (!/\/issues\/\d+(\/|$)/.test(path)) { closeFloat(); refreshScreen(); return; }
    if (!floatSize()) fitFloatHeight(doc); // a size the user dragged stays; otherwise the window fits this issue
    var shownId = issueIdOf(path);
    if (shownId && shownId !== floatIssueId) {
      floatIssueId = shownId;
      var win = document.getElementById('sq-float');
      var subjectEl = doc.querySelector('.issue .subject h3');
      win.querySelector('.sq-float-title').textContent = '#' + shownId + (subjectEl ? ' ' + subjectEl.textContent.trim() : '');
      win.querySelector('.sq-float-open').setAttribute('href', path);
      markSelected();
    }
    if (doc.getElementById('flash_notice')) refreshScreen();
  }

  // The size of the window: dragged at its lower right corner and remembered by the browser; a double click on the
  // corner forgets it. Without one, the window fits the issue when it loads: everything down to two or three lines of
  // the description (a longer description scrolls in its own box), up to 80% of the screen.
  var FLOAT_SIZE_KEY = 'sqFloatSize', MIN_FLOAT_W = 420, MIN_FLOAT_H = 200;

  function floatSize() {
    try { return JSON.parse(window.localStorage.getItem(FLOAT_SIZE_KEY) || 'null'); } catch (e) { return null; }
  }

  function keepFloatOnScreen(win) { // its bottom and right edge stay on the screen
    var overY = win.offsetTop + win.offsetHeight - window.innerHeight;
    var overX = win.offsetLeft + win.offsetWidth - window.innerWidth;
    if (overY > 0 || overX > 0) placeFloat(win, win.offsetLeft - Math.max(0, overX), win.offsetTop - Math.max(0, overY));
  }

  function setFloatSize(win, w, h) {
    if (w) win.style.width = Math.max(MIN_FLOAT_W, Math.min(window.innerWidth - 16, Math.round(w))) + 'px';
    win.style.height = Math.max(MIN_FLOAT_H, Math.min(window.innerHeight - 16, Math.round(h))) + 'px';
    keepFloatOnScreen(win);
  }

  function fitFloatHeight(doc) {
    var win = document.getElementById('sq-float');
    var head = win.querySelector('.sq-float-head').offsetHeight;
    var content = doc.getElementById('content');
    var needed;
    var wiki = doc.querySelector('#content > .issue > .description .wiki');
    if (wiki) {
      var style = doc.defaultView.getComputedStyle(wiki);
      var line = parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.5 || 18;
      needed = wiki.getBoundingClientRect().top + content.scrollTop + line * 3;
      // what stands under the description (the attachments) and the padding at the bottom
      Array.prototype.forEach.call(doc.querySelectorAll('#content > .issue > .description ~ *'), function (el) {
        if (el.id !== 'sq-stage-timeline' && doc.defaultView.getComputedStyle(el).display !== 'none') needed += el.offsetHeight;
      });
      needed += 24;
    } else { // as tall as what the issue shows (the content itself is stretched to the window)
      needed = 0;
      Array.prototype.forEach.call(doc.querySelectorAll('#content > .issue > *, #content > .flash'), function (el) {
        if (doc.defaultView.getComputedStyle(el).display !== 'none') needed = Math.max(needed, el.getBoundingClientRect().bottom + content.scrollTop);
      });
      needed += 24;
    }
    setFloatSize(win, null, head + Math.min(needed, window.innerHeight * 0.8));
  }

  function startFloatResize(event) {
    var win = document.getElementById('sq-float');
    var grip = event.currentTarget;
    event.preventDefault();
    event.stopPropagation();
    var startX = event.clientX, startY = event.clientY;
    var startW = win.offsetWidth, startH = win.offsetHeight;
    grip.classList.add('sq-active');
    if (grip.setPointerCapture) grip.setPointerCapture(event.pointerId);
    var move = function (e) { setFloatSize(win, startW + e.clientX - startX, startH + e.clientY - startY); };
    var done = function () {
      grip.removeEventListener('pointermove', move);
      grip.removeEventListener('pointerup', done);
      grip.removeEventListener('pointercancel', done);
      grip.classList.remove('sq-active');
      try { window.localStorage.setItem(FLOAT_SIZE_KEY, JSON.stringify({ w: win.offsetWidth, h: win.offsetHeight })); } catch (e) { /* ignore */ }
    };
    grip.addEventListener('pointermove', move);
    grip.addEventListener('pointerup', done);
    grip.addEventListener('pointercancel', done);
  }

  function startFloatDrag(event) {
    if (event.target.closest('button, a')) return;
    var win = document.getElementById('sq-float');
    var head = event.currentTarget;
    event.preventDefault();
    var startX = event.clientX, startY = event.clientY;
    var startLeft = win.offsetLeft, startTop = win.offsetTop;
    head.classList.add('sq-active');
    if (head.setPointerCapture) head.setPointerCapture(event.pointerId); // the frame would swallow the moves otherwise
    var move = function (e) { placeFloat(win, startLeft + e.clientX - startX, startTop + e.clientY - startY); };
    var done = function () {
      head.removeEventListener('pointermove', move);
      head.removeEventListener('pointerup', done);
      head.removeEventListener('pointercancel', done);
      head.classList.remove('sq-active');
      try { window.localStorage.setItem(FLOAT_POS_KEY, JSON.stringify({ left: win.offsetLeft, top: win.offsetTop })); } catch (e) { /* ignore */ }
    };
    head.addEventListener('pointermove', move);
    head.addEventListener('pointerup', done);
    head.addEventListener('pointercancel', done);
  }

  // What the iframe loaded: a saved issue comes back with a notice; leaving the issue (deleted, a list) closes the panel
  function onPanelLoad(event) {
    var frame = event.target;
    var doc, path;
    try {
      if (frame.contentWindow.location.href === 'about:blank') return;
      doc = frame.contentDocument;
      path = frame.contentWindow.location.pathname;
    } catch (e) { return; }
    if (!doc) return;
    if (!/\/issues\/\d+(\/|$)/.test(path)) { closePanel(); refreshScreen(); return; }
    // another issue opened inside the panel (its "next" link, a related issue): the mark follows it
    var shownId = issueIdOf(path);
    if (shownId && shownId !== panelIssueId) {
      panelIssueId = shownId;
      var panel = document.getElementById('sq-panel');
      var rowLink = document.querySelector('#sq-root tr.sq-row[data-id="' + shownId + '"] a.sq-subj');
      var subjectEl = doc.querySelector('.issue .subject h3');
      panel.querySelector('.sq-panel-title').textContent = rowLink ? rowLink.textContent.trim()
        : '#' + shownId + (subjectEl ? ' ' + subjectEl.textContent.trim() : '');
      panelUrl = path;
      panel.querySelector('.sq-panel-open').setAttribute('href', path);
      markSelected();
    }
    if (doc.getElementById('flash_notice')) refreshScreen();
  }

  // What to keep over a refresh: scroll positions, the switches of the toolbar, the reorder mode, folded branches, closed groups
  function captureState() {
    var root = document.getElementById('sq-root');
    var scroller = document.querySelector('.sq-scroller');
    var state = { x: scroller ? scroller.scrollLeft : 0, y: scroller ? scroller.scrollTop : 0, pageY: window.scrollY,
                  checks: {}, reorder: !!(root && root.classList.contains('sq-reorder')), folded: [], groups: [],
                  adjust: !!(root && root.classList.contains('sq-adjust')), adjustPush: !adjustFixedDue() };
    each(document.querySelectorAll('input[data-act]'), function (box) { state.checks[box.getAttribute('data-act')] = box.checked; });
    each(document.querySelectorAll('#sq-root tr.sq-collapsed'), function (row) { state.folded.push(row.getAttribute('data-id')); });
    each(document.querySelectorAll('tr.group-header-row'), function (header) {
      var index = header.getAttribute('data-group');
      var rows = document.querySelectorAll('.issue-row.group-child-' + index);
      if (rows.length && rows[0].style.display === 'none') state.groups.push(index);
    });
    return state;
  }

  function restoreState(state) {
    Object.keys(state.checks).forEach(function (act) {
      var box = document.querySelector('input[data-act="' + act + '"]');
      if (box && box.checked !== state.checks[act]) {
        box.checked = state.checks[act];
        box.dispatchEvent(new Event('change', { bubbles: true })); // the same handler as a click
      }
    });
    if (state.reorder) setReorderMode(true);
    if (state.adjustPush) {
      var push = document.querySelector('input[name="sq-adjust-mode"][value="push"]');
      if (push) push.checked = true;
    }
    if (state.adjust) setAdjustMode(true);
    state.folded.forEach(function (id) {
      var row = rowById(id);
      var button = row && row.querySelector('.sq-fold');
      if (button && !row.classList.contains('sq-collapsed')) toggleFold(button);
    });
    state.groups.forEach(function (index) { setGroup(index, false); });
    var scroller = document.querySelector('.sq-scroller');
    if (scroller) { scroller.scrollLeft = state.x; scroller.scrollTop = state.y; }
    window.scrollTo(window.scrollX, state.pageY);
    scheduleLightning();
  }

  // Reads the screen again (same address, same settings) and swaps its content. A refresh asked for while one is on
  // its way is not dropped: it runs again once that one is done (review 2026-11-14: two quick drags in a row).
  var refreshAgain = false;
  function refreshScreen() {
    if (refreshing) { refreshAgain = true; return; }
    refreshing = true;
    refreshAgain = false;
    var state = captureState();
    fetch(window.location.href, { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } })
      .then(function (res) { return res.text(); })
      .then(function (html) {
        var fresh = new DOMParser().parseFromString(html, 'text/html').getElementById('content');
        var current = document.getElementById('content');
        if (!fresh || !current) { window.location.reload(); return; }
        current.replaceWith(document.adoptNode(fresh)); // the parsed nodes themselves: no second parse of the text
        config = null; // the dates of the lightning line may have changed
        initScreen(true);
        restoreState(state);
        markSelected();
      })
      .catch(function () { window.location.reload(); })
      .then(function () {
        refreshing = false;
        if (refreshAgain) refreshScreen();
      });
  }

  // ---- adjust mode -----------------------------------------------------
  // The same adjustments as the issue page's "adjust the schedule", by dragging the bars of a row:
  //  - the right edge of a stage = its deadline. "fixed_due" (due date first): the next stage gives or takes the
  //    days, so the pair keeps its total; the last stage's right edge is the due date: in "fixed_due" it
  //    has no grip and cannot be taken (review 2026-11-14). "push" (days first): only that stage changes, the later
  //    ones and the due date move along;
  //  - the left edge of the first bar = the start date (only while it may move, StageRescheduler#start_changeable?).
  //    "fixed_due": the stage before the due date takes up the difference; "push": everything moves with it;
  //  - the middle of a bar = shift the whole plan (the days stay; the start and the due date move; the tip says so).
  // The row is redrawn while dragging (Esc puts it back); letting go saves that issue at once (a PUT to the issue
  // page's own adjustment, which answers JSON), says so for a moment, and the screen is read again. The date
  // calculation is SqDates (sequential_dates.js), shared with the issue page. The mode is off at every load.

  var EDGE_PX = 6; // how near the edge of a bar the pointer must be to take the edge (wider for a finger)
  var adjusting = null; // the drag in progress

  function adjustRoot() {
    var root = document.getElementById('sq-root');
    return root && root.getAttribute('data-adjust-url') ? root : null;
  }

  function t(name) { var root = adjustRoot(); return (root && root.getAttribute('data-t-' + name)) || ''; }

  function setAdjustMode(on) {
    var root = adjustRoot();
    each(document.querySelectorAll('.sq-adjust-btn'), function (button) {
      button.setAttribute('aria-pressed', on ? 'true' : 'false');
      button.classList.toggle('sq-on', on);
    });
    if (!root || root.classList.contains('sq-adjust') === on) return; // nothing changes: no layout (review 2026-11-14)
    if (on && root.classList.contains('sq-reorder')) setReorderMode(false); // one mode at a time
    root.classList.toggle('sq-adjust', on);
    root.classList.toggle('sq-adj-fixed', adjustFixedDue());
    var bar = root.querySelector('.sq-adjust-bar');
    if (bar) bar.hidden = !on;
    fitScrollers();
    scheduleLightning();
  }

  function adjustFixedDue() {
    var checked = document.querySelector('input[name="sq-adjust-mode"]:checked');
    return !checked || checked.value === 'fixed_due';
  }

  function dates(c) { return c.dates || (c.dates = window.SqDates.make(c.nonWorking)); }

  // The adjustable stages of a row: [{ id, start, end, days, all }], in order
  function rowStages(c, tr) {
    var d = dates(c);
    return tr.getAttribute('data-adj').split(',').map(function (part) {
      var p = part.split(':');
      var start = dayNumber(p[1]), end = dayNumber(p[2]), all = p[3] === '1';
      return { id: p[0], start: start, end: end, all: all, days: Math.max(d.daysBetween(start, end, all), 1) };
    });
  }

  // Puts the row's bars where the planned dates are (the same formula as the page: calendar days across the dates)
  function placeBars(c, a, plan, bad) {
    var t0 = dayNumber(c.timelineStart), t1 = dayNumber(c.timelineEnd);
    plan.forEach(function (st) {
      var bar = a.bars[st.id];
      if (!bar) return;
      var s = Math.max(st.start, t0), e = Math.min(st.end, t1);
      bar.style.left = ((s - t0) * c.dayPx).toFixed(1) + 'px';
      bar.style.width = Math.max((e - s + 1) * c.dayPx - 2, 8).toFixed(1) + 'px';
      bar.classList.toggle('sq-adj-bad', !!bad);
    });
  }

  function showTip(text, x, y, kind) {
    var tip = document.getElementById('sq-adj-tip');
    if (!tip) {
      tip = document.createElement('div');
      tip.id = 'sq-adj-tip';
      tip.setAttribute('role', 'status'); // read out: dates while dragging, "saved", "does not fit"
      tip.setAttribute('aria-live', 'polite');
      document.body.appendChild(tip);
    }
    clearTimeout(tip.hideTimer);
    tip.textContent = text;
    tip.classList.toggle('sq-adj-tip-bad', kind === 'bad');
    tip.classList.toggle('sq-adj-tip-warn', kind === 'warn');
    tip.classList.toggle('sq-adj-tip-ok', kind === 'ok');
    if (x !== null) { tip.style.left = (x + 12) + 'px'; tip.style.top = (y - 28) + 'px'; }
    tip.hidden = false;
  }
  function hideTip(after) {
    var tip = document.getElementById('sq-adj-tip');
    if (!tip) return;
    clearTimeout(tip.hideTimer);
    if (after) tip.hideTimer = setTimeout(function () { tip.hidden = true; }, after);
    else tip.hidden = true;
  }

  // What a press on this bar would do: 'end', 'start', 'move' or null
  function adjustKind(event, bar, tr, stages) {
    var rect = bar.getBoundingClientRect();
    var edge = event.pointerType === 'touch' ? 14 : EDGE_PX;
    var index = stages.findIndex(function (st) { return st.id === bar.getAttribute('data-sid'); });
    var lastFixed = index === stages.length - 1 && stages.length > 1 && adjustFixedDue(); // the due date edge
    var startOk = tr.hasAttribute('data-start-ok');
    if (event.clientX >= rect.right - edge) return lastFixed ? null : 'end';
    if (index === 0 && startOk && event.clientX <= rect.left + edge) return 'start';
    if (startOk) return 'move';
    return null;
  }

  function busy(tr) { return refreshing || tr.classList.contains('sq-adj-saving'); }

  document.addEventListener('pointermove', function (event) {
    if (adjusting) return;
    var bar = event.target.closest && event.target.closest('#sq-root.sq-adjust .sq-bar[data-sid]');
    if (!bar) return;
    var c = config || (config = readConfig());
    var tr = bar.closest('tr');
    var kind = busy(tr) ? null : adjustKind(event, bar, tr, rowStages(c, tr));
    bar.style.cursor = kind === 'end' || kind === 'start' ? 'ew-resize' : (kind === 'move' ? 'grab' : 'not-allowed');
    // why the start cannot move here (the issue page says the same)
    bar.title = tr.hasAttribute('data-start-ok') ? '' : t('start-locked');
  });

  document.addEventListener('pointerdown', function (event) {
    var bar = event.target.closest && event.target.closest('#sq-root.sq-adjust .sq-bar[data-sid]');
    if (!bar || event.button !== 0) return;
    var tr = bar.closest('tr');
    if (busy(tr)) return; // saving or reading the screen again: its data is about to change
    var c = config || (config = readConfig());
    var stages = rowStages(c, tr);
    var kind = adjustKind(event, bar, tr, stages);
    if (!kind) return;
    var days = {}, bars = {};
    stages.forEach(function (st) {
      days[st.id] = st.days;
      bars[st.id] = tr.querySelector('.sq-bar[data-sid="' + st.id + '"]');
    });
    adjusting = { tr: tr, bar: bar, bars: bars, kind: kind, stages: stages, days0: days, x0: event.clientX,
                  index: stages.findIndex(function (st) { return st.id === bar.getAttribute('data-sid'); }),
                  start0: stages[0].start, due: dayNumber(tr.getAttribute('data-due')), changed: false, lastDelta: 0,
                  // "moved" only after most of a day: in the week and month views a day is a few pixels (review 2026-11-14)
                  threshold: Math.max(3, c.dayPx * 0.6) };
    adjusting.result = { days: days, start: stages[0].start, fixed: adjustFixedDue(), bad: false };
    try { bar.setPointerCapture(event.pointerId); } catch (e) { /* a synthetic event */ }
    event.preventDefault();
  });

  // The new plan of the row for the pointer moved by deltaDays
  function adjustTo(a, c, deltaDays) {
    var d = dates(c);
    var fixed = adjustFixedDue();
    var days = {};
    Object.keys(a.days0).forEach(function (id) { days[id] = a.days0[id]; });
    var start = a.start0, bad = false;
    var st = a.stages[a.index];
    var slack = a.stages[a.stages.length - 1];
    if (a.kind === 'end') {
      var end = Math.max(st.end + deltaDays, st.start);
      var n = Math.max(d.daysBetween(st.start, end, st.all), 1);
      var next = a.stages[a.index + 1];
      if (fixed && next) {
        var total = a.days0[st.id] + a.days0[next.id];
        n = Math.min(n, total - 1);
        days[next.id] = total - n;
      }
      days[st.id] = n;
    } else if (a.kind === 'start') {
      start = d.next(a.start0 + deltaDays);
      if (fixed && a.stages.length > 1) { // the first stage takes up the new start; its end stays (2026-11-15)
        var first = a.stages[0];
        var m = d.daysBetween(start, first.end, first.all);
        if (m < 1) bad = true;
        days[first.id] = Math.max(m, 1);
      }
    } else { // move: the days stay, the plan shifts
      start = d.next(a.start0 + deltaDays);
      fixed = false;
    }
    // "fixed_due": the slack is what is left up to the due date, in dates, as the server does
    if (fixed && a.stages.length > 1 && !(a.kind === 'end' && st === slack)) {
      var r = d.slackDays(a.stages.slice(0, -1), slack, start, days, a.due);
      bad = bad || !r.fits;
      days[slack.id] = r.days;
    }
    var plan = d.layout(a.stages, start, days);
    var last = plan[plan.length - 1];
    var tip, kind = null;
    var unit = function (s) { return s.all ? t('unit-all') : t('unit-working'); };
    if (bad) {
      tip = t('cannot-fit').replace('%{date}', window.SqDates.mmdd(a.due));
      kind = 'bad';
    } else if (a.kind === 'end') {
      tip = t('until').replace('%{date}', window.SqDates.mmdd(plan[a.index].end)).replace('%{days}', days[st.id]).replace('%{unit}', unit(st));
    } else {
      tip = t('span').replace('%{start}', window.SqDates.mmdd(plan[0].start)).replace('%{due}', window.SqDates.mmdd(last.end));
    }
    if (!bad && last.end !== a.due) {
      tip += ' ' + t('due-moves'); // the due date moves (days first, or shifting the whole plan)
      if (adjustFixedDue()) kind = 'warn';
    }
    return { days: days, start: start, fixed: fixed, bad: bad, plan: plan, tip: tip, kind: kind };
  }

  document.addEventListener('pointermove', function (event) {
    var a = adjusting;
    if (!a) return;
    var c = config || (config = readConfig());
    var dx = event.clientX - a.x0;
    if (!a.changed && Math.abs(dx) < a.threshold) return;
    var deltaDays = Math.round(dx / c.dayPx);
    if (a.changed && deltaDays === a.lastDelta) { showTip(a.result.tip, event.clientX, event.clientY, a.result.kind); return; }
    a.changed = true;
    a.lastDelta = deltaDays;
    var r = adjustTo(a, c, deltaDays);
    a.result = r;
    placeBars(c, a, r.plan, r.bad);
    showTip(r.tip, event.clientX, event.clientY, r.kind);
  });

  function endAdjust(save) {
    var a = adjusting;
    adjusting = null;
    if (!a || !a.changed) { hideTip(); return; }
    var c = config || (config = readConfig());
    var r = a.result;
    var same = r.start === a.start0 && Object.keys(r.days).every(function (id) { return r.days[id] === a.days0[id]; });
    if (!save || r.bad || same) { // back where it was (a plan that does not fit is not sent; the tip stays a moment)
      placeBars(c, a, dates(c).layout(a.stages, a.start0, a.days0), false);
      if (r.bad && save) hideTip(2000); else hideTip();
      return;
    }
    hideTip();
    var root = adjustRoot();
    var body = ['mode=' + (r.fixed ? 'fixed_due' : 'push')];
    Object.keys(r.days).forEach(function (id) { body.push('stages%5B' + id + '%5D%5Bduration_days%5D=' + r.days[id]); });
    if (r.start !== a.start0) body.push('start_date=' + window.SqDates.ymd(r.start));
    var url = root.getAttribute('data-adjust-url').replace('__ID__', a.tr.getAttribute('data-id'));
    var rect = a.bar.getBoundingClientRect();
    a.tr.classList.add('sq-adj-saving');
    sendPut(url, body.join('&'))
      .then(function (res) { return res.ok ? res.json() : { ok: false }; })
      .then(function (json) {
        if (!json.ok) { window.alert(json.error || t('adjust-failed')); return; }
        // saved: say so for a moment, next to where it happened (review 2026-11-14)
        // which issue: its number and subject, as in the row (shortened when long)
        var link = a.tr.querySelector('a.sq-subj');
        var name = link ? link.textContent.trim() : '#' + a.tr.getAttribute('data-id');
        if (name.length > 40) name = name.slice(0, 39) + '…';
        showTip(t('saved').replace('%{issue}', name), rect.left, rect.top, 'ok');
        hideTip(2500);
      })
      .catch(function () { window.alert(t('adjust-failed')); })
      .then(function () { refreshScreen(); });
  }

  document.addEventListener('pointerup', function () { endAdjust(true); });
  document.addEventListener('pointercancel', function () { endAdjust(false); });
  document.addEventListener('keydown', function (event) { // Esc while dragging puts the row back
    if (event.key === 'Escape' && adjusting) endAdjust(false);
  });
  document.addEventListener('change', function (event) { // the grip on the due date edge follows the mode
    if (event.target.matches && event.target.matches('input[name="sq-adjust-mode"]')) {
      var root = adjustRoot();
      if (root) root.classList.toggle('sq-adj-fixed', adjustFixedDue());
      var hint = document.querySelector('#sq-root .sq-adjust-mode-hint'); // the selected mode in words
      if (hint) hint.textContent = event.target.closest('label').getAttribute('data-hint') || '';
    }
  });

  // ---- delegated listeners and start-up ---------------------------------------------------------

  // all issues at once: collapse or expand every issue that has branches
  function foldAll(collapse) {
    each(document.querySelectorAll('#sq-root button.sq-fold'), function (button) {
      if (button.closest('tr').classList.contains('sq-collapsed') !== collapse) toggleFold(button);
    });
  }

  // Controls of the toolbar (data-act) are outside #sq-root; everything else is inside it
  var TOOLBAR_ACTIONS = {
    'branches-expand': function () { foldAll(false); },
    'branches-collapse': function () { foldAll(true); },
    'groups-expand': function () { toggleAllGroups(true); },
    'groups-collapse': function () { toggleAllGroups(false); }
  };

  function isPlainClick(event) {
    return event.button === 0 && !event.ctrlKey && !event.metaKey && !event.shiftKey && !event.altKey;
  }

  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') { closePanel(); closeFloat(); }
  });

  var barClickTimer = null, DOUBLE_CLICK_WAIT = 250;

  document.addEventListener('dblclick', function (event) {
    var bar = event.target.closest && event.target.closest('#sq-root .sq-bar');
    if (!bar || isInline() || event.target.closest('#sq-root.sq-adjust')) return;
    var link = bar.closest('tr').querySelector('a.sq-subj');
    if (!link) return;
    clearTimeout(barClickTimer);
    event.preventDefault();
    openFloat(link.getAttribute('href'), link.textContent.trim());
  });

  document.addEventListener('click', function (event) {
    var target = event.target;
    if (!target.closest) return;

    var act = target.closest('[data-act]');
    if (act && TOOLBAR_ACTIONS[act.getAttribute('data-act')]) {
      event.preventDefault();
      TOOLBAR_ACTIONS[act.getAttribute('data-act')]();
      return;
    }
    var modeButton = target.closest('.sq-mode-btn');
    if (modeButton) {
      if (modeButton.getAttribute('aria-pressed') !== 'true') setAdjustMode(false); // one mode at a time
      setReorderMode(modeButton.getAttribute('aria-pressed') !== 'true');
      return;
    }
    var adjustButton = target.closest('.sq-adjust-btn');
    if (adjustButton) {
      setAdjustMode(adjustButton.getAttribute('aria-pressed') !== 'true');
      return;
    }
    if (!target.closest('#sq-root')) return;

    var fold = target.closest('button.sq-fold');
    if (fold) {
      toggleFold(fold);
      return;
    }
    var plus = target.closest('a.sq-plus');
    if (plus) {
      event.preventDefault();
      toggleBranchRow(plus);
      return;
    }
    var cancel = target.closest('[data-act="branch-cancel"]');
    if (cancel) {
      var row = cancel.closest('tr');
      if (row) row.parentNode.removeChild(row);
      scheduleLightning();
      return;
    }
    var subject = target.closest('a.sq-subj');
    // while the floating window is open, a click shows the issue in it instead of opening the panel
    if (subject && isPlainClick(event) && floatOpen() && openFloat(subject.getAttribute('href'), subject.textContent.trim())) {
      event.preventDefault();
      return;
    }
    if (subject && isPlainClick(event) && openPanel(subject)) { // Ctrl, Shift and the middle button keep the old way
      event.preventDefault();
      return;
    }
    var bar = target.closest('.sq-bar');
    if (bar && target.closest('#sq-root.sq-adjust')) return; // in the adjust mode a bar is dragged, not opened
    if (bar) {
      var link = bar.closest('tr').querySelector('a.sq-subj');
      if (!link) return;
      if (isInline()) { window.parent.location = link.href; return; }
      clearTimeout(barClickTimer);
      if (floatOpen()) { openFloat(link.getAttribute('href'), link.textContent.trim()); return; } // the window shows it at once
      // a double click on a bar opens the floating window: the single click waits for it a moment
      if (event.detail > 1) return;
      barClickTimer = setTimeout(function () { if (!openPanel(link)) window.location = link.href; }, DOUBLE_CLICK_WAIT);
      return;
    }
    var groupRow = target.closest('tr.group-header-row');
    if (groupRow) toggleGroupCollapse(groupRow.getAttribute('data-group'));
  });

  // The dropdowns and switches of the toolbar are links: a data-nav select goes to the selected option's value,
  // a switch to its data-href
  document.addEventListener('change', function (event) {
    var target = event.target;
    if (!target.matches) return;
    if (target.matches('select[data-nav]')) {
      window.location.href = target.value;
    } else if (target.matches('input[data-href]')) {
      window.location.href = target.getAttribute('data-href');
    } else if (target.matches('input[data-act="lightning"]')) {
      toggleLightningLine(target);
    } else if (target.matches('input[data-act="slow"]')) {
      var rootEl = document.getElementById('sq-root'); // the "usual x1.8" chips of the issue cells
      if (rootEl) rootEl.classList.toggle('sq-slow-off', !target.checked);
      fitScrollers();
    } else if (target.matches('input[data-act="full-view"]')) {
      var page = document.getElementById('sq-root');
      if (page) page.classList.toggle('sq-full', target.checked);
      setFullWidth(target.checked);
      fitScrollers();
      scheduleLightning();
    } else if (target.matches('input[data-act="band-more"]')) {
      // more lanes make the fixed header taller: measure it again
      var root = document.getElementById('sq-root');
      if (root) root.classList.toggle('sq-band-all', target.checked);
      fitScrollers();
      scheduleLightning();
    } else if (target.matches('input[data-act="ms-lines"]')) {
      var lines = document.getElementById('sq-ms-lines');
      if (lines) lines.setAttribute('data-on', target.checked ? '1' : '0');
      scheduleLightning();
    }
  });

  // The order matters: the saved width first (it decides the sizes below), then the scroll position. keepScroll: the
  // screen is read again after a change of an issue: the scroll position is restored by the caller, not set to today
  function initScreen(keepScroll) {
    setReorderMode(false); // the modes are off at every load
    setAdjustMode(false);
    restoreIssueWidth();
    addFoldButtons();
    var links = document.getElementById('sq-branch-folds');
    if (links && document.querySelector('#sq-root button.sq-fold')) links.hidden = false;
    fitScrollers();
    if (!keepScroll) scrollToToday();
    scheduleLightning();
  }

  document.addEventListener('DOMContentLoaded', function () { initScreen(false); });
  // also when the page comes back from the browser's cache: the mode is off again
  window.addEventListener('pageshow', function () { setReorderMode(false); setAdjustMode(false); });
  window.addEventListener('load', function () { fitScrollers(); scheduleLightning(); });
  window.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { fitPanelHeight(); fitScrollers(); scheduleLightning(); }, 100);
  });
})();
