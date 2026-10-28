# Changelog

This project follows Semantic Versioning and Conventional Commits.

## [Unreleased]

### Added

- CSV and PDF export of the status history, from two entry points that share
  one column definition: the inline timeline exports a single issue's full
  history, and the transition search exports every interval matching the
  current filters. One row per interval — issue, tracker, subject, previous
  status, new status, change time, end time, duration and author — so the
  export is the history itself, not the distinct issues the search page
  lists. It reuses the preloaded `search_intervals` scope, so it does not
  re-introduce the N+1 the search fixed.

## [3.0.0] - 2026-10-28

First release of the fork: upstream `redmine_status_history` 2.0.0 ported to
Redmine 7.0.x and hardened for installations large enough for the old
migrations to hurt. The data model is unchanged — an existing installation
keeps its rows and only needs the two steps under **Breaking changes**.

### Added

- Support for Redmine 7.0, with CI on 5.1.13, 6.1.5 and 7.0.2 and the Ruby
  versions each of those branches tests itself against (3.0 to 4.0).
- Inline status timeline on the issue page: status, start date, duration,
  author and the `previous → new` transition, inside the attributes block.
  Plain `<details>`/`<ol>` markup, no JavaScript. Collapsed past 8 intervals.
- Five native issue-query filters — `Status changed to`, `Status changed
  from`, `Status changed on`, `Days in current status`, `Reopen count` — plus
  a sortable `Last status change` column. They work in the issues list, saved
  queries and the CSV export.
- Maintenance tasks: `redmine_status_flow:rebuild`, `verify`, `prune
  CONFIRM=1` and `adopt_legacy_identity`.
- French locale; `es`, `tr` and `zh` completed, with a test that keeps the five
  files in key-for-key parity.
- Duration labels rendered on the model (`< 1min`, `12min`, `4h 12min`,
  `3d 4h`).
- Docker test harness (`bin/test.sh`, `docker/`) that runs the suite against
  Redmine 7.0.2 without installing anything on the host.

### Changed

- Plugin identity is `redmine_status_flow`: plugin id, migration records and
  asset namespace. The Ruby namespace (`RedmineStatusHistory`) and the model
  (`IssueStatusHistory`) keep their upstream names.
- The timeline no longer opens in a modal: the remote link, the `show_history`
  XHR and its `.js.erb` response are gone, and the search page's "View
  history" link jumps to the issue page anchor instead.
- The transition search is paginated through Redmine's own `Paginator` and
  preloads the associations its rows need, so the query count stays flat as
  the result set grows. The form submits with `GET` instead of `POST`: a
  POST-only page cannot be linked, reloaded or paged.
- The historical backfill no longer runs inside migrations 002 and 005, which
  are now no-ops. As a migration it ran `Issue.find_each` with N+1 journal
  loading inside a single transaction — hours of table lock, and a failure
  halfway could not be resumed. Upgrades no longer touch the `issues` table
  for the duration of a migration.
- Column registration goes through `Query.add_available_column` on the class
  instead of appending to a memoized per-instance array, which lost the column
  after the first query and re-appended it on every call.
- The test suite grew from 10 to 28 tests (278 assertions).

### Fixed

- The `IssueQuery` and `JournalDetail` patches were never applied: the guards
  called `include?` where they meant `include`, and the `IssueQuery` guard
  also compared against a module the hook had already replaced. Both patches
  were silently skipped — no error, just a plugin that did less than it
  claimed.
- A history write could fail an ordinary issue update with a 500: the row is
  now inserted inside a savepoint, a failure is logged and the issue save
  proceeds.
- Duplicate intervals from concurrent writes: `journal_id` now carries a unique
  index and a `RecordNotUnique` from a concurrent insert is rescued. The
  `exists?` pre-check stays as a fast path but is no longer what enforces
  uniqueness. Existing duplicates are removed by the migration before the
  index is created.
- The plugin stylesheet 404'd on Redmine 5.x, which copies `assets/` into
  `public/plugin_assets/<id>/` keeping the subdirectories, where 6.0+ flattens
  them behind a single digest-suffixed prefix. The URL is now chosen from the
  Redmine major version. A wrong guess raises nothing: the page simply loads
  unstyled.
- `ActiveRecord.default_timezone` was read from the module, which does not
  expose it before Rails 7. The reader is now taken from whichever object
  provides it, so the plugin loads on Rails 6.1 as well as 7.x and 8.x.
- A missing locale key rendered as `translation missing` (or silently fell
  back) instead of failing. A parity test now asserts that all five locales
  hold the same keys, that every key the plugin asks for is defined, and that
  the pluralized and interpolated ones render.

### Removed

- The modal history endpoint: `show_history` action, its route, the `.js.erb`
  template and the partial only it used.
- `StatusHistoriesHelper`. Its methods were unreachable from any view — a
  plugin is not an engine and Redmine runs with `include_all_helpers = false`,
  so a plugin's helper module is never mixed into the controller that renders
  a view hook. Formatting moved to the model.

### Breaking changes

- **Plugin directory and id.** Install under `plugins/redmine_status_flow`.
  After swapping the directory, run
  `rake redmine_status_flow:adopt_legacy_identity` *before*
  `redmine:plugins:migrate`: migration state is stored under
  `<version>-<plugin_id>` in the shared `schema_migrations` table, so without
  the rewrite Redmine does not recognise the migrations as applied and
  replays them.
- **Backfill.** Migrations no longer populate the history of issues that
  existed before the install. Run `rake redmine_status_flow:rebuild` once
  after upgrading — it produces the timeline those migrations used to create.
  It is idempotent and skips issues that already have intervals, so an
  interrupted run resumes on the next invocation.
- **Redmine upper bound.** `requires_redmine` is now `'5.0'..'7.0'`: Redmine
  7.1 and later refuse to boot the plugin instead of loading code that was
  never run against them.

[Unreleased]: https://github.com/NadLad/redmine_status_flow/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/NadLad/redmine_status_flow/releases/tag/v3.0.0
[2.0.0]: https://github.com/redmineservices/redmine_status_history/releases/tag/v2.0.0
