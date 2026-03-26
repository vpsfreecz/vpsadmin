# Storage topology fixtures

These JSON fixtures capture both sides of a backup topology:

- DB-side storage metadata from `dataset_trees`, `branches`, `snapshot_in_pools`,
  and `snapshot_in_pool_in_branches`
- ZFS-side origin and clone state from `zfs get origin` and `zfs get clones`

They exist so pathological delete-order and rotation cases can be replayed
without reproducing the full live history every time.

Use `capture_backup_topology_fixture(...)` from
`tests/suite/v4/storage/remote-common.nix` during a local integration run to
write a normalized fixture JSON file, for example under `/tmp` inside the test
VM or in a copied-out artifact path.

Each fixture stores:

- a normalized `report`
- the derived delete-order `diagnostic`
- basic `metadata`
- a `generated_at` timestamp

A future broken topology captured from staging or production can be checked into
this directory and replayed with `load_topology_fixture(...)` and
`delete_order_leaf_contract_from_fixture(...)`.
