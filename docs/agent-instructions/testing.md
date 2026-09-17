# Testing and CI

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

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
