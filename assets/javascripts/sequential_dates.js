/*
 * Sequential Tasks: the working-day calculation of the screens, in one place (review 2026-11-14). The same rules as
 * the server (lib/redmine_sequential_tasks/working_day_calculator.rb and StageRescheduler): used by the issue page's
 * "adjust the schedule" (sequential_task_bar.js) and the project timeline's adjust mode (sequential_tasks.js), and
 * by the comparison test (test/js/sequential_dates_test.js, run with node).
 * Dates are day numbers: UTC days since 1970-01-01, so there is no time zone or daylight saving in the way.
 */
(function (root) {
  'use strict';

  var SEARCH_DAYS = 183; // as WorkingDayCalculator::SEARCH_DAYS: no working day in that time = no plan

  function dayNumber(str) { // 'YYYY-MM-DD' -> day number, or null
    if (!str) return null;
    var p = String(str).split('-');
    return Date.UTC(+p[0], +p[1] - 1, +p[2]) / 86400000;
  }

  function ymd(day) {
    var d = new Date(day * 86400000);
    return d.getUTCFullYear() + '-' + ('0' + (d.getUTCMonth() + 1)).slice(-2) + '-' + ('0' + d.getUTCDate()).slice(-2);
  }

  // How the page writes dates (lib/redmine_sequential_tasks/date_format.rb): the patterns come from the element that
  // carries data-sq-date-short. Without one (the node test), the Japanese defaults.
  var formats = null;
  function config() {
    if (formats) return formats;
    var el = typeof document !== 'undefined' && document.querySelector ? document.querySelector('[data-sq-date-short]') : null;
    var months = [];
    try { months = el ? JSON.parse(el.getAttribute('data-sq-months') || '[]') : []; } catch (e) { months = []; }
    formats = { short: (el && el.getAttribute('data-sq-date-short')) || '%m/%d',
                full: (el && el.getAttribute('data-sq-date-full')) || '%Y/%m/%d', months: months };
    return formats;
  }
  function pad(n) { return ('0' + n).slice(-2); }
  // The parts of strftime the patterns use: %Y %y %m %-m %d %-d %e %b %B (Redmine's date formats and ours)
  function format(day, pattern) {
    var d = new Date(day * 86400000), y = d.getUTCFullYear(), m = d.getUTCMonth() + 1, dd = d.getUTCDate();
    var months = config().months;
    return String(pattern).replace(/%(-?)([YymdebB])/g, function (all, flag, c) {
      switch (c) {
        case 'Y': return String(y);
        case 'y': return pad(y % 100);
        case 'm': return flag ? String(m) : pad(m);
        case 'd': return flag ? String(dd) : pad(dd);
        case 'e': return String(dd);
        case 'b': case 'B': return months[m - 1] || pad(m);
      }
      return all;
    });
  }
  function mmdd(day) { return format(day, config().short); }   // the short month and day
  function slashed(day) { return format(day, config().full); } // the full date, as Redmine's setting

  // A calculator for Redmine's non-working week days (1 = Monday .. 7 = Sunday, as Date#cwday)
  function make(nonWorking) {
    var off = (nonWorking || []).map(Number);

    function isWorking(day) {
      var wd = new Date(day * 86400000).getUTCDay(); // 0 = Sunday
      return off.indexOf(wd === 0 ? 7 : wd) < 0;
    }

    // The day itself if it is a working day, else the next one (the day itself when none within SEARCH_DAYS:
    // the screens do not offer adjusting then)
    function next(day) {
      for (var i = 0; i < SEARCH_DAYS; i++) if (isWorking(day + i)) return day + i;
      return day;
    }

    // The last day of a stage of `days` days starting on `start` (moved to a working day first): working days,
    // or every day when allDays
    function endOf(start, days, allDays) {
      var cur = next(start);
      days = Math.max(days | 0, 1);
      if (allDays) return cur + days - 1;
      for (var left = days - 1; left > 0;) {
        var nxt = next(cur + 1);
        if (nxt === cur + 1 && !isWorking(nxt)) return cur; // no working day left (bounded)
        cur = nxt;
        left--;
      }
      return cur;
    }

    // Days of a stage from a to b, both included: working days, or every day when allDays
    function daysBetween(a, b, allDays) {
      if (b < a) return 0;
      if (allDays) return b - a + 1;
      var n = 0;
      for (var d = a; d <= b; d++) if (isWorking(d)) n++;
      return n;
    }

    // Lays stages [{ id, all }] out from `start` with `days` ({ id: n }), as StageRescheduler#build:
    // each stage starts on the next working day after the one before. Returns [{ id, start, end, days }].
    function layout(stages, start, days) {
      var cur = start;
      return stages.map(function (st) {
        var s = next(cur);
        var e = endOf(s, days[st.id], st.all);
        cur = e + 1;
        return { id: st.id, start: s, end: e, days: days[st.id] };
      });
    }

    // "Due date first" (StageRescheduler#call_fixed): the others laid out from `start`, then the slack gets the days
    // from the next working day up to `due`, counted its own way. Returns { days, fits }.
    function slackDays(others, slack, start, days, due) {
      var from = start;
      if (others.length) {
        var laid = layout(others, start, days);
        from = laid[laid.length - 1].end + 1;
      }
      var n = daysBetween(next(from), due, slack.all);
      return { days: Math.max(n, 1), fits: n >= 1 };
    }

    return { isWorking: isWorking, next: next, endOf: endOf, daysBetween: daysBetween, layout: layout, slackDays: slackDays };
  }

  var SqDates = { SEARCH_DAYS: SEARCH_DAYS, dayNumber: dayNumber, ymd: ymd, mmdd: mmdd, slashed: slashed, format: format, make: make };
  root.SqDates = SqDates;
  if (typeof module !== 'undefined' && module.exports) module.exports = SqDates;
})(typeof window !== 'undefined' ? window : this);
