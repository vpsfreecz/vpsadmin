# Storage

vpsAdmin manages ZFS datasets for VPS disks, shared storage, and backups. The
API records the logical dataset separately from its copies on individual
storage pools, so one dataset can have a primary copy and several backups.

## Objects and pool roles

| Object | Meaning |
| --- | --- |
| `Pool` | A configured ZFS filesystem on a node, with a role and capacity settings. |
| `Dataset` | The logical dataset, its owner, hierarchy, and current history identifier. |
| `DatasetInPool` | One dataset's presence on a particular pool. |
| `Snapshot` | A snapshot of the logical dataset. |
| `SnapshotInPool` | A snapshot's presence on a particular dataset in a pool. |
| `DatasetTree`, `Branch` | The backup history structure described in [backup branching](branching.md). |

A pool's `filesystem` is the root of its managed dataset layout. The roles are:

- `hypervisor`: storage used for VPS datasets.
- `primary`: primary storage, including datasets exported for use by VPSes.
- `backup`: backup copies with trees and branches that preserve history across
  rollback and replacement of the primary dataset.

Source: [Pool](../../api/models/pool.rb),
[Dataset](../../api/models/dataset.rb), and
[DatasetInPool](../../api/models/dataset_in_pool.rb).

## Operations

Storage operations run through [transaction chains](../transactions.md).
The API acquires locks, prepares database records, and schedules commands on
the relevant nodes. Confirmations reconcile the records with the outcome.
Use the API for managed storage changes so that ZFS state and those records
remain consistent.

### Create and configure

Creation prepares the dataset and its `DatasetInPool`, properties, resource
allocation, and any required mounts. A logical dataset retained after removal
of its primary copy can be reused; creation clears its expiration.

Property changes and inheritance have separate transaction chains. Their
validation and propagation are part of the API's dataset property handling.

Source: [create](../../api/models/transaction_chains/dataset/create.rb),
[set](../../api/models/transaction_chains/dataset/set.rb), and
[inherit](../../api/models/transaction_chains/dataset/inherit.rb).

### Snapshot and transfer

Snapshot operations create a snapshot on the selected pool. Transfers use
ZFS streams to copy snapshots between pools, using an incremental stream
when a common snapshot exists. A backup destination can start a new tree
when the histories no longer share a snapshot.

Source: [snapshot](../../api/models/transaction_chains/dataset/snapshot.rb),
[transfer](../../api/models/transaction_chains/dataset/transfer.rb), and
[send](../../api/models/transaction_chains/dataset/send.rb).

### Rollback and restore

For a snapshot present on the primary pool, rollback can use the local ZFS
snapshot. When the snapshot is available only in backup storage, vpsAdmin
transfers it to a temporary dataset and replaces the primary dataset while
preserving its subdatasets. Backup branching preserves the later backup
history where applicable.

A VPS restore wraps dataset rollback with VPS stop/start operations. It also
locks the VPS. Dataset rollback and VPS restore therefore have different
coordination requirements even when they target the same snapshot.

Source: [dataset rollback](../../api/models/transaction_chains/dataset/rollback.rb)
and [VPS restore](../../api/models/transaction_chains/vps/restore.rb).

### Retention and removal

Snapshot rotation uses `min_snapshots`, `max_snapshots`, and
`snapshot_max_age`. Referenced snapshots are skipped. On source pools,
rotation also checks that an open backup's live head retains a newer shared
source snapshot before removing an older one. These constraints can retain
more snapshots than the configured maximum.

Removing a dataset from a pool can also remove its subdatasets, snapshots,
mounts, exports, and scheduled actions. When only backup copies remain, the
logical dataset receives an expiration date. When no copies remain, its
record is removed. The deletion chain and [lifetime processing](../object-lifetimes.md)
handle these steps; removing primary storage does not immediately delete all
its backups.

Source: [rotation](../../api/models/transaction_chains/dataset/rotate.rb) and
[dataset-in-pool removal](../../api/models/transaction_chains/dataset_in_pool/destroy.rb).

## Scheduled work and downloads

Dataset plans and repeatable tasks schedule operations such as snapshots,
backup transfers, and rotation. Their implementation is in
[dataset plans](../../api/lib/vpsadmin/api/dataset_plans.rb),
[dataset actions](../../api/models/dataset_action.rb), and
[repeatable tasks](../../api/models/repeatable_task.rb).

[Snapshot downloads](download.md) export archives or ZFS streams for retrieval
over HTTP. They also support local ZFS backups through `vpsadminctl`.
