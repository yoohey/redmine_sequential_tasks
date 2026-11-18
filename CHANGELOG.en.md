# Changelog

The main changes of each version. The same content goes on the GitHub Releases.

[日本語](CHANGELOG.md)

## 0.9.1 (2026-11-17)

Small fixes to 0.9.0. No database changes.

### Fixed

- **How dates are written**: full dates (the history details, tips, milestones and so on) follow Redmine's "Date format" setting (Administration > Settings > Display). Short month-and-day dates follow the language (Japanese "11/16", English "Nov 16"). They were fixed before.
- **Names**: the module in the project settings and the view permission in the roles showed English names even on Japanese screens; they now have names in both languages.
- **The tracker settings**:
  - Leaving the page with unsaved changes asks first.
  - The color samples are larger and have names for screen readers; a color chosen in the color picker marks the sample of the same color.
  - "(not in the workflow)" explains what it means and what to do.
  - Saving stages while the tracker is not enabled tells so.
  - The page's styles and scripts moved to files, so a strict CSP or a dark theme breaks it less.
- **The timeline**: the lightning line, slowness, ◆ lines and band switches have tips. On the matrix, the tracker filter sits with the other filters.

### Updating

No database changes. Replace `plugins/redmine_sequential_tasks/` and restart Redmine.

## 0.9.0 (2026-11-16)

The first public release. For all the features, see the [README](README.en.md) and the [manual](docs/MANUAL.en.md). The changes since 0.8.0 are:

### New

- **The tab can be renamed**: with "Tab name" in the plugin settings (Administration → Plugins → Configure), rename the tab in the project menu and the headings of the timeline, the matrix and the analysis (when blank, "Sequential Tasks"; up to 30 characters).
- **Changing the tracker of an existing issue to a sequential one creates its stages**: as when an issue is created, the stages are laid out from the start date with the standard days, and the due date is set to the end of the plan. If a person who may not change the start or due date by the workflow makes the change and that date would move, the save is refused.
- **Adjust mode** (the timeline's "📅 Adjust"): the "saved" notice shows the number and subject of the issue.
- **Touch, keyboard and screen readers**: in "Adjust schedule" on the issue page, the handles are easier to grab, the day fields are wider and have accessible names. The explanation of the mode and the reason why the start date cannot be changed are shown on the screen. Esc cancels the adjustment.

### Changed

- **"Due date first" now always means "only the neighbor of the moved boundary changes"**: changing the start date stretches or shrinks only the first stage. Switching "Count non-working days" counts the days of that stage again, keeping its dates.
- **"Ahead" is shown on weekends and non-working days too**: on a day that falls in no stage, the issue is compared with the stage it should have been in on the last working day before (previously, no issue was "Ahead" on weekends).
- **An issue created with a start date in the future** shows its first stage as "Planned" until the start date comes (no actual start is shown). The time spent in the analysis is also counted from the planned start.

### Other

- Added the manual ([docs/MANUAL.en.md](docs/MANUAL.en.md)). The images and videos show made-up data. The release zip does not include the images.
- The license is now GPLv2 or any later version (the same as Redmine).

### How to update

There is no database change since 0.8.0. Replace `plugins/redmine_sequential_tasks/` with the new version and restart Redmine. For a first installation, see "Installation" in the README.

### What has been checked

- The tests all pass on both Redmine 6.1.5 and 7.0.2. The screens on 7.0.2 have not been checked.
- The screens have been checked in the author's environment (Redmine 6.1.5, PostgreSQL 17, a Chromium-based browser). Redmine 6.0.x, MySQL and SQLite, Firefox and Safari have not been checked.

## Versions before the public release

Versions released in the author's environment, used while building it, before the public repository was made.

- **0.8.0** (2026-11-14): CSV of the matrix, stages that count non-working days, no plan when the settings leave no working day, the shading of the timeline follows the non-working days setting, the look of the adjust mode. Fixed bugs such as the plan breaking when the start and due dates were changed at once. Input limits, guards against mistakes, CSV formula neutralization. Database change (migration 007).
- **0.7.0** (2026-11-14): adjusting the plan ("Adjust schedule" on the issue page, with Due date first and Days first; adjusting the start date), the timeline's "📅 Adjust" mode, the bar on the issue page looks the same as on the timeline.
- **0.6.0** (2026-11-12): the 0-day stage (waiting to be picked up). Database change (migration 006).
- **0.5.0** (2026-11-12): standard days per project, and the permission "Adjust the standard days". Database change (migration 005).
- **0.4.0** (2026-11-12): on the page of an issue with branches, a timeline of that issue and its branches. Finished stages drawn pale. The bar style per tracker. Database change (migration 004).
- **0.3.0** (2026-11-12): the tracker settings screen rebuilt, three bar styles, a switch for the slow-stage chips. Security fixes (limits on the values of stage colors, branches created from a private parent, getting around read-only fields of the workflow).
- **0.2.0** (2026-11-12): the side panel on the right, to edit an issue while looking at the timeline.
- **0.1.0** (2026-11-12): the first version. Plan vs. actual of stages, the timeline, milestones and phase bands, whether a release will be met, loose branches, reordering, the matrix, the analysis, full view and printing.
