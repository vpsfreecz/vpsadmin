# Integration tests

This tree reuses the vpsAdminOS test framework via the flake input. The
`./test-runner.sh` wrapper runs the vpsadminos test-runner and evaluates this
repo's flake outputs (`tests` and `testsMeta`), so no `NIX_PATH` or local
vpsadminos checkout is required.

## Running tests

- Use `./test-runner.sh ls` (list tests), `./test-runner.sh test services-up`
  for the service smoke test, or `./test-runner.sh test 'webui#*'` for all
  Playwright browser tests.
- Individual webui browser components can be run by script, for example
  `./test-runner.sh test 'webui#auth'` or
  `./test-runner.sh test 'webui#vps-lifecycle'`.
- The runner supports the usual flags from vpsAdminOS; run
  `./test-runner.sh --help` for details.
- CI uses test-runner metadata expressions to run affected integration areas,
  e.g. `./test-runner.sh test --filter 'tag=ci && (tag=vps || tag=storage)'`.
  Path selection rules live in `tests/ci-selection.yml`; derived test and
  webui script tags are added by `tests/ci-tags.nix` through `tests/make-test.nix`.

## Test layout

- `tests/all-tests.nix` mirrors the vpsAdminOS layout so the runner can
  discover tests (the runner evaluates the `testsMeta` flake output).
- `tests/make-test.nix` delegates to the vpsAdminOS test framework via the
  `vpsadminosPath` suite argument.
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
