# Integration tests

This tree reuses the vpsAdminOS test framework without copying it. It expects
the `vpsadminos` repository to be checked out next to this one (or point
`VPSADMINOS_PATH` elsewhere) so the runner can add it to `NIX_PATH` and import
`<vpsadminos/tests/make-test.nix>` to build the shared test runner.

## Running tests

- Build/run the runner from this repo: `./test-runner.sh list` (lists available
  tests) or `./test-runner.sh run vpsadmin/services-up`. The wrapper builds
  `os/packages/test-runner/entry.nix` from vpsAdminOS and runs it with the
  current working directory set to this repository.
- The runner respects the usual flags from vpsAdminOS (e.g. `--state-dir`,
  `--jobs`, `--stop-on-failure`); see `<vpsadminos/test-runner/man>` for details.

## Test layout

- `tests/all-tests.nix` mirrors the vpsAdminOS layout so the runner can
  discover tests (the runner loads its own `list-tests.nix` from vpsAdminOS).
- `tests/make-test.nix` delegates to `<vpsadminos/tests/make-test.nix>`.
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

This is a starting point for multi-node tests; add more VMs using the same
socket network and share common setup through the configs above.
