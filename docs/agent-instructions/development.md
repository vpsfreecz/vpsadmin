# Development commands

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

## Build, Test, and Development Commands
- Enter a dev shell with flakes: `nix develop` (or `nix develop .#vpsadmin`) for root actions, and `nix develop .#api` / `nix develop .#webui` / `nix develop .#client` / `nix develop .#console-router` / `nix develop .#nodectl` / `nix develop .#nodectld` / `nix develop .#libnodectld` for component scopes.
- API: `cd api && bundle install && bundle exec rspec`; lint with `bundle exec rubocop`; local run via `bundle exec rackup -p 9292 config.ru`.
- API and libnodectld RSpec suites need MariaDB. In local Nix dev shells,
  `bundle exec rspec` starts an isolated temporary test database automatically
  when neither `DATABASE_URL` nor `api/config/database.yml` is configured. Use
  `VPSADMIN_TEST_DB_AUTO=0` to disable automatic startup.
- For manual database debugging from `api/` or `libnodectld/`, use
  `../tools/test-db start`, `eval "$(../tools/test-db env)"`,
  `../tools/test-db status`, `../tools/test-db client`,
  `../tools/test-db stop`, and `../tools/test-db prune`. The default URL is
  `mysql2://root:root@127.0.0.1:13306/vpsadmin_test`; libnodectld specs append
  `_libnodectld` through their shared DB setup.
- Web UI: `composer install --working-dir=webui`; browser integration tests run with `./test-runner.sh test webui`.
- Nix builds: `nix-build packages -A <attr>` or `nix-build nixos -A <module>` for module outputs.
