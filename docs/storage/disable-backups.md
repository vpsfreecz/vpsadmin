# Disabling scheduled backups and removing source snapshots

`Dataset.DisableBackups` is an administrator-only operation that removes dataset
plans and all snapshots on the selected primary or hypervisor copy. It preserves
the live filesystem, dataset identity, quotas and VPS running state. Ordinary
`Dataset.Plan.Delete` only removes its schedule: existing snapshots on both source
and backup pools remain in place.

The endpoint is `POST /v7.0/datasets/:dataset_id/disable_backups`. Input uses the
normal `dataset` envelope:

```json
{"dataset":{"recursive":false,"backup_first":true}}
```

`recursive` defaults to false. True selects the existing dataset subtree,
including its root; separately mounted datasets outside that subtree are excluded.
Each dataset must have exactly one current primary or hypervisor copy, belong to
the same owner and pass lifetime, maintenance and storage-state checks. Plans
need not exist. Known source references, clones, mounts, pending transitions,
conflicting locks or unsupported automation reject the entire request.
Resolve these blockers through their ordinary managed operations; cleanup does
not force unmounts or remove ZFS holds.

## Preservation before cleanup

`backup_first` defaults to true. Every selected source snapshot must be preserved
on **every existing open backup copy for that dataset** before source destruction.
Confirmed copies with confirmed branch memberships in retained non-head trees
count. Otherwise, an ordinary transfer in the same chain must copy the snapshot;
receive checks verify each newly copied snapshot before cleanup. Unrelated
pending copies do not count. A nonempty source without an open destination rejects
the entire request; empty sources need no destination. Closed backup pools are
neither reopened nor used as preservation targets.

Target availability checks apply to nonempty sources with `backup_first:true`.
With explicit opt-out or an empty source, cleanup changes only metadata on backup
copies, so it can detach confirmed heads while a backup node is unavailable.
Source safety checks, all-copy locks and pending-state checks still apply.

Preservation copies existing snapshots only, without taking a new snapshot of
the live filesystem or running source or backup rotation. Transfers use their
ordinary incremental selection and existing initial-full/no-common-history paths.
If an older or middle snapshot is missing below a newer backup head and ordinary
transfer cannot copy it, the request fails before any work is queued. The error
identifies the uncovered snapshot and destination. There is no special gap repair
or automatic opt-out. Multiple destinations and normal full transfers can require
substantial time, bandwidth and storage.

Explicit `backup_first:false` skips preservation and permits loss of source-only
restore points, including manual and untransferred snapshots. It is never an
automatic fallback after transfer failure.

## One task and its receipt

With an administrator CLI profile, submit one operation and let the CLI wait for
the ordinary task:

```sh
vpsadminctl dataset disable_backups DATASET_ID
```

Add `-- --recursive` to include the subtree. Use the CLI's usual `--no-block`
option before the resource to return after acceptance; it does not cancel work.

Submit the action once. The ordinary HaveAPI success envelope contains
`response._meta.action_state_id`, alongside an empty `dataset` container, with no
action-specific fields:

```json
{"status":true,"response":{"dataset":{},"_meta":{"action_state_id":123}}}
```

Use the ordinary action-state polling facility or the transaction task view to
wait for that task. Accepted work continues if the browser or CLI exits. Empty
and metadata-only requests also return a task. Confirm completion by waiting for
the task to finish successfully, then refreshing plans and snapshots. If the
submission outcome is unknown, inspect existing tasks and reconcile the request
before deliberately retrying; do not submit again automatically.

All transfers and receive checks across the whole recursive scope precede plan
removal, head detachment and source snapshot destruction. Plan removal and head
edits use ordinary confirmations at chain closure. Plans can remain visible while
work is pending; source locks prevent scheduled work or plan mutation from using
them. Scheduled actions recheck their action or group membership after acquiring
source locks, so already loaded work cannot recreate snapshots after removal.
Unaffected members of a shared snapshot group continue normally.

## Failure and recovery

A construction error rolls back all preparation and queues no chain. A reversible
transfer or receive-check failure prevents every cleanup follower from executing;
source snapshots and plans remain. Ordinary rollback may remove copies created
by that failed attempt. Fatal rollback retains locks for reconciliation.

The metadata and destruction suffix is irreversible, including helper steps.
A failure there cannot roll back successful preservation. A metadata failure may
apply some successful plan/head changes but cannot have deleted source snapshots
yet. A later source deletion failure can partly succeed, for example when an
unmanaged ZFS hold blocks one snapshot. Successful metadata changes and completed
deletions confirm; failed and future source copies remain. Inspect the task,
confirmations and actual node state, then refresh plans and snapshots before
retrying known remaining work. A failed task must not be reported as completed.
Removing a lock alone does not reconcile storage. Software rollback cannot
restore deleted source-only snapshots.

The operation retains backup copies, trees, branches and snapshots. Existing
backup retention and later independent deletion remain effective; this action
does not exempt history from retention indefinitely. On successful completion,
all associated backup tree and branch heads are detached, including closed-pool
heads, and all selected source snapshots and plans are gone.

## Reenabling and compatibility

Assign the intended plans normally to enable scheduled backups again. Because
successful disabling detached the heads, the next snapshot and transfer start a
new tree with a full first stream; later snapshots in that tree can transfer
incrementally. Empty sources create no tree until a later snapshot exists.
Ordinary plan assignment does not reset heads, and deliberate restore or manual
transfer operations retain their existing head behavior. For recursive cleanup,
reassign the intended plan separately to each dataset.

The operation uses existing node commands and wire parameters. It requires no
database migration or storage format change. Deploy the API and scheduler safety
guards together and drain or restart older workers before exposing the action. Older workers lack the necessary plan
locks and scheduled membership checks. Complete or reconcile pending chains before
backend rollback, and remove clients' cleanup affordance before removing API
support. Rollback cannot restore removed snapshots or schedules. Schema export,
generated-client synchronization and client publication remain separate delivery
steps under the [API export procedure](../api-schema-export.md).

Implementation: [operation](../../api/lib/vpsadmin/api/operations/dataset/disable_backups.rb)
and [chain](../../api/models/transaction_chains/dataset/disable_backups.rb).
