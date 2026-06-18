# Integration tests

This tree reuses the vpsAdminOS test framework via the flake input. The
`./test-runner.sh` wrapper runs the vpsadminos test-runner and evaluates this
repo's flake outputs (`tests` and `testsMeta`), so no `NIX_PATH` or local
vpsadminos checkout is required.

## Running tests

- Use `./test-runner.sh ls` (list tests), `./test-runner.sh test services-up`
  for the service smoke test, or `./test-runner.sh test 'webui#*'` for all
  Playwright browser tests.
- Individual webui browser components can be run by script. List current
  scripts with `./test-runner.sh ls 'webui#*'`, then run one with
  `./test-runner.sh test 'webui#<script-name>'`.
- The runner supports the usual flags from vpsAdminOS; run
  `./test-runner.sh --help` for details.
- CI uses test-runner metadata expressions to run affected integration areas,
  e.g. `./test-runner.sh test --filter 'tag=ci && (tag=vps || tag=storage)'`.
  Path selection rules live in `tests/ci-selection.yml`; derived test and
  webui script tags are added by `tests/ci-tags.nix` through `tests/make-test.nix`.

## Manual webhook testing

Use `tools/webhook-test-server.rb` inside the services VM when testing
notification webhooks from the dev cluster. Binding to VM localhost avoids host
firewall and routing issues. The dev cluster allows webhook delivery to
loopback addresses; production deployments should allow only the private ranges
they intentionally want users to reach:

```sh
cd /path/to/vpsfree.cz-workspace
dev-clusters/vpsadmin/bin/devcluster ssh <cluster-slug> services
cd /mnt/vpsadmin
ruby_bin=$(find /nix/store -maxdepth 3 -type f -path '*/bin/ruby' | grep 'ruby-[0-9]' | head -n 1)
"$ruby_bin" tools/webhook-test-server.rb --host 127.0.0.1 --port 18080
```

Configure the receiver action URL as:

```text
http://127.0.0.1:18080/events
```

The server writes the latest request to `/tmp/vpsadmin-webhook-test/request.json`
inside the services VM and prints one line for each received request. If it has
to run on the host instead, bind `--host 0.0.0.0`, open the host firewall or use
a tunnel, and configure an address reachable from the services VM.

## Webui Playwright coverage

The webui application root is `webui/`. Only browser entrypoints and assets
belong under `webui/public/`, which is the nginx document root. PHP
application code, config samples, Composer files, `vendor/`, language files,
forms, pages, and `webui/template/template.html` stay outside the document root.

Changes under `webui/` that affect user-visible behaviour should be covered by
the relevant Playwright browser test when practical. This includes page/form
changes, navigation, auth/session flows, role-specific behaviour, JavaScript,
and template changes that can break rendered workflows. Cosmetic-only or
dead-code changes may not need new coverage, but they should still run the
closest existing script when the affected page is already covered.

Run the full webui browser suite with:

```sh
./test-runner.sh test 'webui#*'
```

List the current webui scripts with:

```sh
./test-runner.sh ls 'webui#*'
```

Run targeted scripts while developing by passing a listed script name:

```sh
./test-runner.sh test 'webui#<script-name>'
```

When adding a new Playwright script, wire it into `tests/suite/webui.nix`,
`tests/ci-tags.nix`, and `tests/ci-selection.yml` so local runs and selective
CI can address it by script/tag.

## Webui PHPUnit coverage

Fast PHP regression tests for shared helpers and source-level security
guardrails live under `webui/tests/`. Run them with:

```sh
nix develop .#webui --command bash -lc 'composer install && composer test'
```

Use PHPUnit for helper-level regressions that do not need a browser or service
VM. Keep Playwright for rendered workflows, authentication/session behavior,
role-specific browser behavior, and JavaScript interactions.

## CI test selection

The CI workflow in `.github/workflows/ci.yml` runs the full integration suite
on a weekly schedule and for manual full runs. For normal pushes it diffs the
pushed commits, runs `tools/select_ci_tests.rb`, and passes the resulting
metadata expression to the test runner:

```sh
./test-runner.sh test --filter 'tag=ci && (tag=vps || tag=storage-backup)'
```

Selection is intentionally conservative. If a changed runtime file is not
matched by `tests/ci-selection.yml`, CI falls back to `tag=ci` and runs the
whole integration suite. Documentation-only, spec-only, and webui PHPUnit-only
changes can be skipped by the integration workflow when all changed files match
the `skip` rules.

When adding, moving, or renaming files that affect runtime behaviour, update
`tests/ci-selection.yml` in the same change. Map the path to the smallest
reasonable set of tags, but prefer a broader tag over missing coverage. For
example, a shared VPS helper should select `vps`, while migration-specific code
should select `vps-migrate` and any related storage tag such as
`storage-migrate`.

When adding or renaming integration tests, check that the derived tags in
`tests/ci-tags.nix` still describe the new test name. The broad `ci` tag stays
in the test file; additional tags are injected centrally by
`tests/make-test.nix`. Add explicit rules to `tests/ci-tags.nix` when a new
test does not fit the existing name-based conventions.

When adding or renaming webui Playwright scripts in `tests/suite/webui.nix`,
also update:

- `tests/ci-tags.nix`, so the script can be selected with a `webui-*` tag;
- `tests/ci-selection.yml`, so matching PHP/JS/spec changes route to that
  script;
- this README if the new script introduces a new selection area.

Useful validation commands:

```sh
ruby tests/ci-selection-test.rb
printf '%s\n' webui/pages/page_login.php | ruby tools/select_ci_tests.rb
./test-runner.sh ls --filter 'tag=ci'
./test-runner.sh ls --filter 'tag=ci && (tag=webui-auth || tag=webui-transactions)'
./test-runner.sh ls --filter 'tag=ci && (tag=vps-migrate || tag=storage-backup)'
```

## Test layout

- `tests/all-tests.nix` mirrors the vpsAdminOS layout so the runner can
  discover tests (the runner evaluates the `testsMeta` flake output).
- `tests/make-test.nix` delegates to the vpsAdminOS flake-exported
  `testFramework`.
- `tests/configs/nixos/vpsadmin-services.nix` defines a NixOS VM profile with
  API, supervisor, console_router, webui, varnish, frontend, rabbitmq and redis.
  It:
  - uses user-mode networking plus a socket link on `eth1` (default
    `192.168.10.10`; extend `/etc/hosts` via `vpsadmin.test.socketPeers`);
  - seeds MariaDB with a `vpsadmin` user/password and runs migrations
    automatically;
  - configures RabbitMQ/Redis with simple test credentials stored under
    `/etc/vpsadmin-test/`.
- `tests/suite/services-up.nix` boots the service VM and asserts core
  units start, migrations ran (`users` table exists) and key ports respond.
- `tests/suite/webui.nix` boots the same service VM and exposes independent
  Playwright scripts for auth/session, user namespace, and VPS lifecycle
  browser coverage.

## Cluster definitions

- Predefined nodes with IDs and socket IPs live in `api/db/seeds/test-nodes.nix`
  (`node1`/`node2` vpsadminos hypervisors plus `storage1`/`storage2` storage
  nodes).
- Cluster seed files such as `api/db/seeds/test-1-node.nix` call
  `mkClusterSeed` with `nodeRefs` to pick which predefined nodes to include;
  Node and PortReservation seed data are generated for the chosen nodes.
- Machine definitions in `tests/machines/cluster/*.nix` import the same
  cluster seed and pass `clusterSeed.nodes` into `mk-cluster.nix`, so adding a
  new cluster only requires a thin wrapper that lists the nodes to include.

This is a starting point for multi-node tests; add more VMs using the same
socket network and share common setup through the configs above.
