# Redmine Status Flow

[![Test](https://github.com/NadLad/redmine_status_flow/actions/workflows/test.yml/badge.svg)](https://github.com/NadLad/redmine_status_flow/actions/workflows/test.yml)
![Redmine](https://img.shields.io/badge/Redmine-5.0%20%7C%206.x%20%7C%207.0-B32024)
![Ruby](https://img.shields.io/badge/Ruby-3.0--4.0-CC342D?logo=ruby&logoColor=white)
[![License](https://img.shields.io/github/license/NadLad/redmine_status_flow)](LICENSE)

Status history for Redmine issues: every status an issue has been through, how
long it stayed there, and native issue-query filters to find issues by those
transitions.

The plugin stores one row per **status interval** — a status, the moment it
started, and the moment it ended (`NULL` while the status is still current).
That single table drives three surfaces: the inline timeline on the issue page,
a project-level transition search, and five filters plus one sortable column in
Redmine's own query builder.

It is a fork of
[`redmineservices/redmine_status_history`](https://github.com/redmineservices/redmine_status_history)
2.0.0, ported to Redmine 7.0.x and hardened for larger installations.

## Why this fork exists

Upstream 2.0.0 declares support up to Redmine 6.1 and is not tested beyond it.
Moving it to 7.0 exposed failures that are silent rather than loud: patches
that were never applied because of a guard bug, a write path that could return
500 on an ordinary issue update, and — introduced by the port itself — an asset
URL that 404s on 5.x without raising. This fork fixes those at the root instead
of patching around them.

| Concern | Upstream 2.0.0 | 3.0.0 |
| --- | --- | --- |
| Redmine | 5.0 – 6.1 | 5.0 – 7.0, with an upper bound |
| Timeline | modal, opened by XHR (`showModal` + `.js.erb`) | inline partial on the issue page |
| Backfill | inside migrations 002/005, one transaction, hours of table lock | `rake redmine_status_flow:rebuild`, batched and resumable |
| Issue writes | `create!` inside `after_create` could fail the issue save | savepoint, failure logged, save unaffected |
| Duplicate rows | `exists?` check, which is a race | unique index on `journal_id` |
| Query filters | last status change only | five status-flow filters plus a sortable column |
| Locales | en, es, tr, zh, with gaps | plus `fr`, with a parity test |
| Tests | 10 | 28 (278 assertions) |

## Features

- **Inline status timeline** on the issue page: status, date, duration, author
  and the `previous → new` transition, rendered inside the attributes block.
  No modal, no XHR. Collapsed by default when an issue has more than 8 intervals.
- **Transition search** inside a project: destination status, optional previous
  status, and a date range. Results are issues, paginated, with associations
  preloaded.
- **Five native query filters** for issue queries, plus the `Last status change`
  date filter and sortable column.
- **Compact duration labels** (`< 1min`, `12min`, `4h 12min`, `3d 4h`).
- **Project permission** (`Search issue status history`) guarding both the
  search page and its results.

## Compatibility

| Plugin | Redmine | Ruby | Rails |
| --- | --- | --- | --- |
| 3.0.x | 5.0.x – 7.0.x | 3.0 – 4.0 | 6.1 – 8.1 |

CI runs the suite on Redmine 5.1.13, 6.1.5 and 7.0.2, with the Ruby versions
each of those branches itself supports (3.0/3.2, 3.2/3.4, 3.2/3.3/3.4/4.0).
The plugin declares `requires_redmine version: '5.0'..'7.0'`: a Redmine version
above 7.0 (7.1 included) is refused at boot instead of loading code that was
never run against it.

No extra gem is required. Use whichever database Redmine itself supports.

## Installation

From the Redmine directory:

```sh
cd plugins
git clone https://github.com/NadLad/redmine_status_flow.git
cd ..
bundle exec rake redmine:plugins:migrate NAME=redmine_status_flow RAILS_ENV=production
```

Then:

1. Restart Redmine.
2. Go to **Administration → Roles and permissions** and grant
   **Search issue status history** to the roles that need it.
3. Build the history of issues that existed before the install:

   ```sh
   bundle exec rake redmine_status_flow:rebuild RAILS_ENV=production
   ```

   The task is batched (`BATCH_SIZE`, default 500), idempotent, and can be
   limited to one project with `PROJECT_ID=<id>`. Status changes made after the
   install are recorded automatically; the backfill only concerns the past.

Migrations 002 and 005 are deliberately no-ops: the backfill they used to run
now lives in the rake task above, so an upgrade never holds the `issues` table
for hours inside a migration transaction.

## Upgrading from `redmine_status_history`

Back up the database first. The table, its columns and the Ruby model are
unchanged, so existing rows are kept as-is; only the plugin identity and its
migration bookkeeping change.

```sh
cd /path/to/redmine/plugins
mv redmine_status_history redmine_status_history.bak
git clone https://github.com/NadLad/redmine_status_flow.git
cd ..
bundle exec rake redmine_status_flow:adopt_legacy_identity RAILS_ENV=production
bundle exec rake redmine:plugins:migrate NAME=redmine_status_flow RAILS_ENV=production
```

`adopt_legacy_identity` rewrites the `schema_migrations` rows recorded under the
legacy plugin id (`redmine_status_history`) to the new one, dropping a legacy
row when the new one already exists. Without it, Redmine does not recognise the
migrations as applied and replays them. It is idempotent and prints
`nothing to adopt` on a fresh install.

Restart Redmine afterwards. If the timeline of older issues looks incomplete,
run `redmine_status_flow:verify` then `rebuild` (see
[Maintenance tasks](#maintenance-tasks)).

## Usage

### Status timeline

Open an issue. The timeline sits at the bottom of the attributes block and
lists every interval in chronological order:

| Column | Meaning |
| --- | --- |
| Status | the status that was active |
| Created / Changed | when the interval started (`Created` for the first one, which is the issue's creation) |
| Duration | how long the status lasted (`< 1min`; the current status shows its running age) |
| Author | who made the change |
| Transition | `previous → new`, when a previous status is known |

The first row is the issue's creation; the last one (no end date) is its current
status. The block starts collapsed when the history has more than 8 intervals,
so a long history does not push the description off the screen.

### Transition search

On a project's issue list, the **Search issue changes** link (visible only with
the permission) opens the search page. Available fields:

- **Status to** — the destination status.
- **Status from** — optional previous status.
- **From / To** — the date range the change must fall in.

The form submits with `GET`, so a search can be bookmarked, shared or reloaded
with pagination intact. Results are issues, not intervals: one row per matching
issue, whatever the number of matching transitions. An invalid or inverted date
range shows an error message and runs no query.

### Query filters and column

All filters are registered through Redmine's standard issue query builder, so
they work in the issues list, in saved queries and in the CSV export.

| Filter | Type | Matches |
| --- | --- | --- |
| Status changed to | status list | the issue has a change into one of the selected statuses (the creation row never matches) |
| Status changed from | status list | the issue has a change out of one of the selected statuses |
| Status changed on | date | the change happened inside the date range |
| Days in current status | integer | age, in days, of the interval that is still open |
| Reopen count | integer | number of transitions from a closed status to an open one |
| Last status change | date | date of the newest interval; also available as the sortable **Last status change** column |

Two definitions worth knowing:

- **Closed** is whatever `IssueStatus#is_closed` says *now*. Moving a status
  in or out of the closed set reinterprets the existing history.
- The filters use `EXISTS`/`COUNT` subqueries rather than joins. A join would
  multiply issue rows (one per interval) and break Redmine's pagination count.

## Maintenance tasks

| Task | What it does |
| --- | --- |
| `redmine_status_flow:rebuild` | Builds missing intervals from journal details. `BATCH_SIZE`, `PROJECT_ID` and `FORCE=1` (delete the existing intervals first) are supported. Idempotent without `FORCE`. |
| `redmine_status_flow:verify` | Read-only. Reports orphan rows, issues with no history and a stale `last_status_update`; exits `1` when anything is found. |
| `redmine_status_flow:prune CONFIRM=1` | Deletes orphan rows (history rows whose journal was deleted without the callbacks) and repairs `last_status_update`. Destructive: back up first, and run `verify` to see what it would act on. |
| `redmine_status_flow:adopt_legacy_identity` | Rewrites migration rows recorded under `redmine_status_history`. Idempotent. |

A healthy installation answers `verify: clean`.

## Data model

`issue_status_histories` holds one row per interval:

| Column | Meaning |
| --- | --- |
| `issue_id` | the issue |
| `status_id` | status during the interval |
| `previous_status_id` | status it came from, `NULL` for the creation row |
| `journal_id` | the journal that caused the change, `NULL` for the creation row |
| `user_id` | who made the change |
| `from` | interval start |
| `to` | interval end, `NULL` while the status is current |

`issues.last_status_update` mirrors the newest interval start so the query
builder can filter and sort without touching the history table. It is written
by an `after_create` callback and recomputed by `rebuild` / `prune`.

Journal details produce at most one interval each, enforced by a unique index on
`journal_id`; the creation row is exempt because no two `NULL`s collide in a
unique index on the supported engines.

## Plugin identity

The plugin id is `redmine_status_flow`, taken from the symbol passed to
`Redmine::Plugin.register` — not from the directory name. Migration state lives
in Redmine's shared `schema_migrations` table as `<version>-redmine_status_flow`.

The Ruby namespace (`RedmineStatusHistory`) and the model (`IssueStatusHistory`)
keep their upstream names: they are code identifiers, not plugin identity, and
renaming them would break every existing reference for no functional gain.

## Development

Nothing runs on the host. `bin/test.sh` drives a Docker image built from
`docker/Dockerfile.test` — the official `redmine:7.0.2` image plus sqlite3, the
gems Redmine's `test_helper` needs and the core test schema — and mounts the
plugin inside it. A local Redmine checkout is never mounted, so no root-owned
file lands in it.

The image must exist before the first run: `bin/test.sh build` creates it, and
rebuilds it after a change to `docker/Dockerfile.test`.

```sh
bin/test.sh build   # build the image (or rebuild after changing Dockerfile.test)
bin/test.sh test    # migrate the plugin and run the suite (default)
bin/test.sh boot    # boot Redmine in the test environment, list loaded plugins
bin/test.sh shell   # shell in the image with the plugin mounted
```

The current suite is **28 runs, 278 assertions, 0 failures**. To run a single
file, use `bin/test.sh shell` and, inside the image:

```sh
RAILS_ENV=test bundle exec rake redmine:plugins:migrate NAME=redmine_status_flow
RAILS_ENV=test bundle exec ruby -Itest plugins/redmine_status_flow/test/unit/locales_test.rb
```

CI (`.github/workflows/test.yml`) repeats the same suite on eight
Redmine/Ruby combinations across 5.1, 6.1 and 7.0. Each job also uninstalls and
reinstalls the plugin to prove the migrations are reversible, runs `rebuild`
then `verify`, and precompiles the assets to catch a stylesheet registration
that would otherwise 404 silently.

Porting notes, measured evidence and the remaining backlog live in
[`docs/`](docs/). See [CONTRIBUTING.md](CONTRIBUTING.md) for how to submit
changes, and [SECURITY.md](SECURITY.md) before reporting a vulnerability.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| The timeline is empty for issues created before the install | migrations do not backfill | `rake redmine_status_flow:rebuild` |
| `verify` reports stale `last_status_update` | a status change never reached the column (import, direct SQL, restored backup) | `rake redmine_status_flow:prune CONFIRM=1` |
| `redmine:plugins:migrate` replays migrations after the rename | rows still recorded under `redmine_status_history` | `rake redmine_status_flow:adopt_legacy_identity` |
| The issue page is unstyled | the plugin stylesheet is not registered (`404` is silent) | run `assets:precompile` on 6.0+; on 5.x check `public/plugin_assets/redmine_status_flow/` |
| The **Search issue changes** link is missing, or the page redirects to login | the role lacks the permission | grant **Search issue status history** to the project roles |

## Credits and license

Fork maintained by [Nader Lad](https://github.com/NadLad), based on
[`redmine_status_history`](https://github.com/redmineservices/redmine_status_history)
by Redmine Services.

Licensed under the GNU General Public License v2.0, inherited from upstream.
See [LICENSE](LICENSE).
