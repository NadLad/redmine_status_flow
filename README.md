# Redmine Status Flow

[![Tests](https://github.com/NadLad/redmine_status_flow/actions/workflows/test.yml/badge.svg?branch=redmine-7)](https://github.com/NadLad/redmine_status_flow/actions/workflows/test.yml)
![Redmine](https://img.shields.io/badge/Redmine-5.x%20%7C%206.x%20%7C%207.x-B32024)
![Ruby](https://img.shields.io/badge/Ruby-3.1--4.0-CC342D?logo=ruby&logoColor=white)
[![License](https://img.shields.io/github/license/NadLad/redmine_status_flow)](LICENSE)

`redmine_status_flow` records every issue status interval, exposes the status
timeline on the issue page, and adds status-transition filters and columns to
the standard issue query builder.

It is a fork of
[`redmineservices/redmine_status_history`](https://github.com/redmineservices/redmine_status_history)
(2.0.0) with Redmine 7.0 support, hardened callbacks and a batched backfill.

## Features

- Status timeline rendered inline on the issue page (no modal, no XHR).
- Search status transitions within a project and date range.
- Optionally filter by both the previous and destination statuses.
- Filter and sort issue queries by the last status-change date.
- Restrict access with a project permission.

## Compatibility

| Plugin | Redmine | Ruby | Rails |
| --- | --- | --- | --- |
| 2.0.x | 5.0.x, 5.1.x, 6.0.x, 6.1.x | 3.1 - 3.3 | 6.1 - 7.2 |
| 3.0.x | 5.0.x - 7.0.x | 3.1 - 4.0 | 6.1 - 8.1 |

Redmine 7.0.2 (Ruby 4.0.8, Rails 8.1.4) is covered by CI. The plugin declares
`requires_redmine version: '5.0'..'7.0'`, so a Redmine major above 7 is refused
at boot instead of loading unverified code.

## Installation

From the Redmine directory:

```sh
cd plugins
git clone https://github.com/NadLad/redmine_status_flow.git
cd ..
bundle exec rake redmine:plugins:migrate NAME=redmine_status_flow RAILS_ENV=production
```

Restart Redmine and grant **Search issue status history** to the appropriate
project roles.

The backfill of existing issues is **not** part of the migration anymore: run
`bundle exec rake redmine_status_flow:rebuild` once, after the migration, in
batches. On large installations this avoids the multi-hour migration and its
long table lock.

## Plugin identity

The plugin id is `redmine_status_flow`, derived from the symbol passed to
`Redmine::Plugin.register` — not from the directory name. Migration state lives
in the shared `schema_migrations` table under `<version>-<plugin_id>`.

The Ruby namespace stays `RedmineStatusHistory` and the model stays
`IssueStatusHistory`: they are code identifiers, not plugin identity, and
renaming them would break every existing reference for no functional gain.

## Upgrade from `redmine_status_history`

Back up the database first, then:

```sh
cd plugins
mv redmine_status_history redmine_status_flow
cd ..
bundle exec rake redmine_status_flow:adopt_legacy_identity RAILS_ENV=production
bundle exec rake redmine:plugins:migrate NAME=redmine_status_flow RAILS_ENV=production
```

`adopt_legacy_identity` rewrites the migration rows recorded under the legacy
id so Redmine does not replay them. It is idempotent and reports `nothing to
adopt` on a fresh install.

## Usage

Open a project's issue list and select **Search issue changes**. Choose the
destination status, optional previous status and date range. The result list
links to each matching issue.

The issue page shows the status timeline inline, and the standard issue query
builder exposes **Last status change** as a date filter and sortable column.

## Uninstallation

Back up the database, then run:

```sh
bundle exec rake redmine:plugins:migrate NAME=redmine_status_flow VERSION=0 RAILS_ENV=production
```

Remove the plugin directory and restart Redmine.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md). Please report security issues according
to [SECURITY.md](SECURITY.md).

## License

This project is licensed under the GNU General Public License v2.0 or later,
inherited from the upstream project. See [LICENSE](LICENSE).
