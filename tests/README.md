# Integration tests

This tree reuses the vpsAdminOS test framework via the flake input. The
`./test-runner.sh` wrapper runs the vpsadminos test-runner and evaluates this
repo's flake outputs (`tests` and `testsMeta`), so no `NIX_PATH` or local
vpsadminos checkout is required.

## Running tests

- Use `./test-runner.sh ls` (list tests) or
  `./test-runner.sh test vpsadmin/services-up`.
- The runner supports the usual flags from vpsAdminOS; run
  `./test-runner.sh --help` for details.

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
- `tests/suite/vpsadmin/services-up.nix` boots the service VM and asserts core
  units start, migrations ran (`users` table exists) and key ports respond.

## Cluster definitions

- Predefined nodes with IDs and socket IPs live in `api/db/seeds/test-nodes.nix`
  (`node1`/`node2` vpsadminos hypervisors plus `storage1`/`storage2` storage
  nodes).
- Cluster seed files such as `api/db/seeds/test-1-node.nix` call
  `mkClusterSeed` with `nodeRefs` to pick which predefined nodes to include;
  Node and PortReservation seed data are generated for the chosen nodes.
- Machine definitions in `tests/machines/v4/cluster/*.nix` import the same
  cluster seed and pass `clusterSeed.nodes` into `mk-cluster.nix`, so adding a
  new cluster only requires a thin wrapper that lists the nodes to include.

This is a starting point for multi-node tests; add more VMs using the same
socket network and share common setup through the configs above.
