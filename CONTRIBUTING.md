# Contributing

Bug reports and pull requests are welcome. Target the `main` branch, keep
changes focused, use Conventional Commits, and cover a behaviour change with a
test.

## Running the suite

Nothing needs to be installed on the host. From the plugin directory:

```sh
bin/test.sh test
```

That uses the `redmine_status_flow-test` image (Redmine 7.0.2 plus the gems and
schema Redmine's `test_helper` expects), migrates the plugin and runs the
suite. Create the image first with `bin/test.sh build`, and rebuild it after a
change to `docker/Dockerfile.test`; `bin/test.sh shell` opens a shell inside
it. See [Development](README.md#development) for single-file runs.

CI runs the same suite on Redmine 5.1.13, 6.1.5 and 7.0.2 with the Ruby
versions each branch supports, and also checks that the migrations uninstall
cleanly. A change that only works on one version should not merge.

## Reporting

Do not include credentials, personal data or customer data in issues, tests or
fixtures. Reproduce with Redmine's own fixtures instead.
