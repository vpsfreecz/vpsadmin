# Storage topology fixtures

These fixtures store the normalized backup-topology shape used by the storage
integration helpers. They let CI and local debugging replay delete-order and
leaf-set diagnostics without rebuilding the original backup history every time.

## Fixture schema

Each fixture JSON file contains:

- `version`: currently `1`
- `generated_at`: ISO8601 timestamp
- `metadata`: free-form object for case names, notes, expected leaf-match state,
  chain ids, and similar context
- `report`: normalized topology report with:
  - `db.trees`
  - `db.branches`
  - `db.entries`
  - `zfs.origins`
  - `zfs.clones`
- `diagnostic`: the derived `delete_order_diagnostic(report)` payload

If `metadata.expected_leaf_sets_match` is present, fixture validation also
checks it against `delete_order_leaf_contract(report)['leaf_sets_match']`.

## Capture from integration tests

The storage helpers in `tests/suite/v4/storage/remote-common.nix` support
optional artifact capture during local runs. Set `STORAGE_TOPOLOGY_FIXTURE_DIR`
to a writable directory and the pending storage suites will write normalized
fixtures there when they reach the capture points.

```text
mkdir -p /tmp/storage-fixtures
STORAGE_TOPOLOGY_FIXTURE_DIR=/tmp/storage-fixtures \
  ./test-runner.sh test v4/storage/repeated-rollback-branching
```

Those suites now emit `before`/`after` fixture files when capture is enabled.

## Capture from a live system

For offline diagnosis against a real database plus ZFS host, use
`api/bin/storage-topology-fixture`:

```text
cd api
bundle exec ruby bin/storage-topology-fixture \
  --db-host 127.0.0.1 \
  --db-port 3306 \
  --db-user root \
  --db-pass secret \
  --db-name vpsadmin \
  --dip-id 123 \
  --backup-dataset-path tank/backup/my-dataset \
  --output ../tests/suite/v4/storage/fixtures/example.json \
  --case repeated-rollback-branching \
  --expected-leaf-sets-match false \
  --generated-at 2026-01-01T00:00:00Z
```

The tool reads:

- DB metadata from `dataset_trees`, `branches`, `snapshot_in_pools`,
  `snapshot_in_pool_in_branches`, and `snapshots`
- ZFS topology from `zfs get origin` and `zfs get clones`

## Validate fixtures

Use `api/bin/storage-topology-check` to verify schema, normalization, and the
recomputed diagnostic:

```text
cd api
bundle exec ruby bin/storage-topology-check \
  ../tests/suite/v4/storage/fixtures/synthetic-good-topology.json
```

To fail when the fixture's leaf sets do not match, add:

```text
cd api
bundle exec ruby bin/storage-topology-check \
  --require-leaf-match \
  ../tests/suite/v4/storage/fixtures/synthetic-good-topology.json
```

## Replay in CI

Committed fixtures under this directory are exercised by
`tests/suite/v4/storage/topology-fixture-replay.nix`, which validates:

- fixture shape
- report normalization stability
- diagnostic stability
- optional `expected_leaf_sets_match` contracts

## Sanitization

If a fixture originated from staging or production, sanitize hostnames, dataset
names, notes, and any other identifying metadata before committing it to this
repository.
