# Strict group snapshot contract

Run `tests/contracts/storage_group_snapshot_v4/run.sh` from the repository
worktree. It starts one disposable MariaDB instance, runs the API producer in
`nix develop .#api`, then runs the NodeCtld consumer in
`nix develop .#libnodectld`. On success, the runner confirms that the database
listener has stopped, reports elapsed seconds, and removes its private state.
On failure, it returns a nonzero status and retains mode 0700 diagnostics. It
keeps the disposable database URL out of stdout and CI logs.

The API process stages three real, signed one-command 5215 chains under the
test-only strict opt-in. The Node process reads the same rows through its real
database and command path. It replaces only physical inventory and handler ZFS
calls with bounded in-memory effects. It checks success, identity-bound partial
compensation, and refusal of an extra Pool observer target before any effect.
The consumer does not load NodeCtld's usual spec helper, which would reload
another database.

The dedicated `storage-group-snapshot-contract.yml` workflow runs this script
when its contract or owning API/Node files change. Integration CI skips these
contract files in `tests/ci-selection.yml`; the workflow runs them directly.
The existing API and Node unit spec workflows remain separate.
`cleanup_test.sh` uses fake commands to check stop failure, a lingering
listener, and retention of an earlier test failure without starting MariaDB.

This fixture exercises a test-only strict path. Production strict dispatch
stays disabled. The test does not use host ZFS or production services.
