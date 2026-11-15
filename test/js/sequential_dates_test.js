// The screens' date calculation (assets/javascripts/sequential_dates.js) gives the same results as the server
// (WorkingDayCalculator, StageRescheduler): the same cases as test/unit/working_day_calculator_test.rb and
// test/unit/stage_rescheduler_test.rb. Run: node test/js/sequential_dates_test.js (no Redmine needed).
'use strict';
const assert = require('assert');
const D = require('../../assets/javascripts/sequential_dates.js');

const c = D.make([6, 7]); // Saturday, Sunday
const day = D.dayNumber;
const fmt = D.ymd;
let n = 0;
function check(name, fn) { fn(); n++; console.log('ok', name); }

check('a working day stays, a weekend moves to Monday', () => {
  assert.strictEqual(fmt(c.next(day('2026-11-02'))), '2026-11-02');
  assert.strictEqual(fmt(c.next(day('2026-10-31'))), '2026-11-02');
});
check('3 working days from Monday end on Wednesday', () => {
  assert.strictEqual(fmt(c.endOf(day('2026-11-02'), 3, false)), '2026-11-04');
});
check('a stage over the weekend skips it', () => {
  assert.strictEqual(fmt(c.endOf(day('2026-11-05'), 3, false)), '2026-11-09'); // Thu, Fri, Mon
});
check('starting on a weekend begins on Monday', () => {
  assert.strictEqual(fmt(c.endOf(day('2026-10-31'), 1, false)), '2026-11-02');
});
check('a stage that counts every day runs over the weekend', () => {
  assert.strictEqual(fmt(c.endOf(day('2026-11-04'), 4, true)), '2026-11-07'); // Wed..Sat
});
check('days between, both ways of counting', () => {
  assert.strictEqual(c.daysBetween(day('2026-11-02'), day('2026-11-06'), false), 5);
  assert.strictEqual(c.daysBetween(day('2026-10-31'), day('2026-11-01'), false), 0);
  assert.strictEqual(c.daysBetween(day('2026-11-04'), day('2026-11-05'), true), 2);
});
check('layout: the next stage starts on the next working day', () => {
  const plan = c.layout([{ id: 2, all: true }, { id: 3, all: false }], day('2026-11-04'), { 2: 4, 3: 2 });
  assert.deepStrictEqual(plan.map((p) => [fmt(p.start), fmt(p.end)]), [['2026-11-04', '2026-11-07'], ['2026-11-09', '2026-11-10']]);
});
check('due date first: +1 day on stage 2 shrinks the slack (stage_rescheduler_test)', () => {
  // stage 2: 11/04..11/05 (2 days) -> 3; slack stage 3 ends 11/09
  const r = c.slackDays([{ id: 2, all: false }], { id: 3, all: false }, day('2026-11-04'), { 2: 3, 3: 2 }, day('2026-11-09'));
  assert.deepStrictEqual(r, { days: 1, fits: true });
});
check('due date first: no room left does not fit', () => {
  const r = c.slackDays([{ id: 2, all: false }], { id: 3, all: false }, day('2026-11-04'), { 2: 4, 3: 2 }, day('2026-11-09'));
  assert.strictEqual(r.fits, false);
});
check('due date first with a slack that counts every day keeps the due date', () => {
  const r = c.slackDays([{ id: 2, all: false }], { id: 3, all: true }, day('2026-11-04'), { 2: 3, 3: 4 }, day('2026-11-09'));
  assert.deepStrictEqual(r, { days: 1, fits: true }); // stage 2 ends Fri; the slack runs Mon..Mon
});
check('every day non-working: no endless loop', () => {
  const none = D.make([1, 2, 3, 4, 5, 6, 7]);
  assert.strictEqual(typeof none.endOf(day('2026-11-02'), 5, false), 'number');
});
console.log(n + ' checks passed');
