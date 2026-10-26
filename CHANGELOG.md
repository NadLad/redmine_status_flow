# Changelog

This project follows Semantic Versioning and Conventional Commits.

## [Unreleased]

### Added

- Docker test harness (`bin/test.sh`, `docker/`) that runs the suite against
  Redmine 7.0.2 without installing anything on the host.

## [2.0.0] - 2026-08-05

### Added

- Support for Redmine 5.0, 5.1, 6.0 and 6.1.
- Automated compatibility tests and reversible migration checks.
- Public installation, contribution and security documentation.

### Changed

- Modernized the Redmine model patches and issue-query integration.
- Made historical data migrations deterministic and reversible.
- Added database indexes for project history lookups.

### Fixed

- Initial histories now support an absent previous status and journal.
- Issues without journaled status changes are populated correctly.
- Status intervals are stored and displayed in chronological order.

### Security

- Enforced the project permission on every endpoint.
- Scoped issue timelines and search results by project and issue visibility.
- Validated search dates before querying.

[2.0.0]: https://github.com/redmineservices/redmine_status_history/releases/tag/v2.0.0
