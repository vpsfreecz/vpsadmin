# Backup branching

Backup pools retain snapshot histories that can diverge from the current
primary dataset. Trees separate incompatible histories; branches preserve
snapshots newer than a rollback target.

## Trees, branches, and heads

A dataset on a backup pool contains ZFS datasets named `tree.<index>`. Each
tree contains datasets named `branch-<name>.<index>`. Tree indexes increase as
new histories are created. Branch names come from the creation time or the
snapshot used to create the branch; an index distinguishes repeated names.

For example, a backup dataset can have this layout:

```text
storage/backup/101/
  tree.0/
    branch-2026-09-01T00:00:00.0/
      @2026-09-01T00:00:00
      @2026-09-02T00:00:00
      @2026-09-03T00:00:00
```

The API records the current head tree and head branch. Incoming snapshots go
to that branch. Each subdataset has its own backup tree and branch structure.
A `SnapshotInPoolInBranch` record identifies a snapshot's location in a branch
and can also record its dependency on another branch's snapshot.

Source: [DatasetTree](../../api/models/dataset_tree.rb),
[Branch](../../api/models/branch.rb), and
[branch membership](../../api/models/snapshot_in_pool_in_branch.rb).

## Rollback creates a new continuation of history

Suppose a branch contains snapshots A, B, C, D, and E, and the primary dataset
is rolled back to C. The backup must retain D and E while accepting new
snapshots from the restored state.

When a new branch is needed, vpsAdmin clones C and promotes the clone. The
snapshots through C move to the promoted branch; D and E remain in the old
branch. The new branch becomes the head:

```text
before rollback:
  original branch: A B C D E

after rollback to C:
  head branch:     A B C
  original branch:       D E  (depends on C)

after another backup:
  head branch:     A B C F
  original branch:       D E  (depends on C)
```

C must remain while the old branch depends on it. The API records this
relationship and updates reference counts. When the target is already the tip
of the selected branch, it can reuse that branch instead of creating another.
Rolling back to a snapshot in another tree can also change the head tree.

Source: [backup branching during rollback](../../api/models/transaction_chains/dataset/rollback.rb)
and [node branch operation](../../libnodectld/lib/nodectld/commands/branch/create.rb).

## Interrupted history

An incremental transfer needs a common snapshot between the source and the
backup's current head. Reinstalling a VPS replaces its root filesystem history
and detaches the backup heads. Transfers also detect a missing common snapshot
and create a new tree on a backup destination. Earlier trees remain available
until retention or deletion removes them.

Trees keep these histories separate: a snapshot in one tree is not a valid
incremental base for an unrelated tree. A new tree starts with a full transfer;
subsequent transfers can be incremental.

Source: [transfer selection](../../api/models/transaction_chains/dataset/transfer.rb)
and [VPS reinstall](../../api/models/transaction_chains/vps/reinstall.rb).

## Rotation and dependencies

Rotation considers snapshot age and retention counts, but it cannot remove a
snapshot with active references. In the example above, C remains while D and
E depend on it. Removing dependent branch entries reduces the reference count
and can make their origin eligible for a later rotation.

Removing the last live entry from a branch also removes that branch. Removing
the last branch from a tree removes the tree. A snapshot can have entries in
more than one branch, so deleting one entry does not necessarily remove its
`SnapshotInPool` record.

Use the managed storage operations to preserve the relationship between ZFS
clones, branch membership, and reference counts.

Source: [rotation](../../api/models/transaction_chains/dataset/rotate.rb) and
[snapshot removal](../../api/models/transaction_chains/snapshot_in_pool/destroy.rb).
