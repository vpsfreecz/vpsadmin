# Repository Guidelines

## Project Structure & Module Organization
- `api/`: Ruby 3.4 API with business logic, migrations in `db/migrate`, specs in `spec/`, plugins under `plugins/`.
- `webui/`: PHP front end (Composer-managed); config samples near `config_cfg.php`.
- `client/`, `nodectl*/`, `nodectld*/`, `libnodectld*/`: CLI tools and node daemons, each with its own `Gemfile`/`.rubocop.yml`.
- `nixos/`, `packages/`: NixOS modules and Nix package definitions for deployments.
- `doc/`: Architecture notes (`overview.mdwn`, `transactions.mdwn`) and operational docs.

## Relationship With vpsAdminOS
- vpsAdmin commonly drives vpsAdminOS feature needs, but vpsAdminOS remains an
  independent general-purpose container host platform.
- When a vpsAdmin feature needs vpsAdminOS changes, keep vpsAdmin-specific
  policy, database semantics, backup ownership, and orchestration in vpsAdmin
  or nodectld/libnodectld integration code where possible.
- Shape osctld/osctl-facing requests as reusable primitives that make sense for
  non-vpsAdmin users. If a vpsAdmin-specific contract is unavoidable, document
  the boundary and compatibility expectations in the change.

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

## Coding Style & Naming Conventions
- Ruby: target Ruby 3.4, 2-space indent, snake_case. Run `bundle exec rubocop` in the touched component.
- PHP/JS in `webui`: mirror nearby code style; avoid sprawling scripts.
- Tests: name specs `*_spec.rb` with clear example names.
- Plugins: keep plugin gems inside the plugin directory; they are pulled via the `### vpsAdmin plugin marker ###` in `api/Gemfile`.
- Database schema: `api/db/schema.rb` is for core vpsAdmin tables only. Dump it
  from a core-only environment, e.g. with `VPSADMIN_PLUGINS=none`; plugin
  tables belong in `plugins/*/api/db/migrate` and must not be committed to the
  core schema file.

## Localization
- API translations are maintained in `api/lib/vpsadmin/api/locales/*.yml` and
  normalized by `rake vpsadmin:i18n:update`.
- vpsAdmin sets HaveAPI `parameter_i18n_scope` to the `vpsadmin` application
  root. Parameter labels/descriptions are generated under
  `vpsadmin.resources`, `vpsadmin.attributes`, and `vpsadmin.meta`; do not add a
  separate `vpsadmin.parameters` tree.
- The locale files include generated key structure from API source and HaveAPI
  parameter metadata. Edit translations in the locale files, then regenerate.

## Testing Guidelines
- Integration tests live in `tests/` and reuse the vpsAdminOS test framework via the flake input, so no sibling `vpsadminos` checkout or `NIX_PATH` setup is required.
- For local gem development of `libnodectld`, `nodectl`, or `nodectld` against a checkout, set `VPSADMINOS_PATH=/path/to/vpsadminos`.
- Run `rake vpsadmin:gems` to refresh all packaged Ruby gem metadata. Use
  `rake -T vpsadmin:gems` to list individual package tasks when only one
  package has to be refreshed. Do not create build IDs or upload first-party
  gems to a remote RubyGems repository.
- Use `./test-runner.sh ls` to enumerate tests and `./test-runner.sh test <test>` (e.g. `services-up`).
- Test definitions are in `tests/all-tests.nix` and `tests/suite/*`; machines compose `tests/machines/cluster/*.nix` plus seeds from `api/db/seeds/test*.nix` to spin up services and vpsAdminOS nodes on user+socket networks.
- Tests that transfer, migrate, reinstall, replace, back up, or restore a VPS
  dataset must verify data integrity when the operation is expected to preserve
  data. Create a file at a known path with known contents, or an equivalent
  payload checksum, before the operation and assert that it survives intact on
  the destination or restored dataset.
- Services VM config `tests/configs/nixos/vpsadmin-services.nix` seeds MariaDB/RabbitMQ/Redis credentials from `tests/configs/nixos/vpsadmin-credentials.nix`, enables API/webui/supervisor/console_router; adjust socket addresses via `vpsadmin.test.*`.
- Scenarios include cluster smoke tests, node registration, VPS create/start, and VPS migrate between nodes; expect long-running Nix builds/VM boots rather than quick unit specs.
- test-runner extension `tests/runner/extensions/vpsadmin_services.rb` adds a `vpsadminctl` helper and `wait_for_vpsadmin_api` for machines tagged `vpsadmin-services`.
- Changes under `webui/` that affect user-visible behaviour should be covered
  by relevant Playwright browser tests when practical. Run all webui scripts
  with `./test-runner.sh test 'webui#*'`. List current scripts with
  `./test-runner.sh ls 'webui#*'`, then target one with
  `./test-runner.sh test 'webui#<script-name>'`.
- CI (GitHub Actions) runs push integration tests selectively using
  `.github/workflows/ci.yml`, `tools/select_ci_tests.rb`,
  `tests/ci-selection.yml`, and derived metadata tags from `tests/ci-tags.nix`.
  When adding, renaming, or moving runtime files, integration tests, or webui
  Playwright scripts, update the selection rules/tags in the same change so
  affected pushes continue to run the right `tag=ci && (...)` filter. Unknown
  runtime paths intentionally fall back to the full `tag=ci` suite; prefer
  broader tags over under-selecting tests. Validate selector changes with
  `ruby tests/ci-selection-test.rb` and representative
  `./test-runner.sh ls --filter 'tag=ci && (...)'` commands.
- CI (GitHub Actions) runs `api/spec/**` in parallel **topic jobs** defined in `.github/workflows/api-specs.yml`.
  When adding/renaming/moving API spec files, you **must** update the workflow's topic patterns so every spec is covered
  exactly once. The CI job "API specs - topic coverage" will fail if any spec is missing or matches multiple topics.

## Commit & Pull Request Guidelines
- Use short imperative subjects, often scoped (`api: add StoragePool resource`, `webui: fix payset form`); keep one logical change per commit.
- Every commit message must explain what the change does and why it is
  needed; use the subject for the action and the body for the rationale
  when needed.
- Wrap every commit message line at 80 characters or fewer.
- Always write the commit message to a temporary file and commit with
  `git commit -F <tmpfile>` instead of passing the message inline.
- Flake input updates (`vpsadminos`) must be done with
  `tools/update_vpsadminos_flake.sh`. The script reads the current and new
  revs, updates only the `vpsadminos` input, verifies that only `flake.lock`
  changed, and commits with subject format
  `flake: vpsadminos <old9> -> <new9>`.
- PRs should state intent, note risky areas, list test commands run, and link issues; add screenshots/logs for UI/API behavior changes.

## Security & Configuration Tips
- Do not commit secrets; use samples in `api/config` and `webui/` plus local `.env` or Nix overlays.
- When changing Nix modules or deployment code, document option changes in the edited file and call out migrations in the PR.
