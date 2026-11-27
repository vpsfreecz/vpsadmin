# Removing all dataset snapshots

Administrators can preview and remove all managed snapshot history for an active
dataset. Removal includes its primary or hypervisor copy and every backup copy,
including closed backup pools, old trees, non-head branches and empty trees and
branches. It preserves the live filesystem, dataset identity, quotas, properties,
VPS running state and backup destination associations. Datasets without a current
primary or hypervisor source and inactive datasets are unsupported.

This differs from [disabling backups](disable-backups.md), which can preserve
source snapshots on backup storage and retains backup history. Snapshot removal
does not create a final backup. Deleted restore points cannot be recovered by
rolling back the software.

## Review and submit

`Dataset.PreviewSnapshotRemoval` is a nonblocking administrator-only POST to
`/v7.0/datasets/:dataset_id/preview_snapshot_removal`, with the normal dataset
input envelope. `recursive` defaults to false; true selects the existing logical
subtree, including its root. Separately mounted datasets are excluded.
`disable_plans` defaults to true. Explicit false retains schedules, which can
create snapshots again immediately after cleanup completes.

Preview reads a consistent database snapshot without creating a task, resource
lock or preview record. It returns a complete inventory, `manifest_version:1`
and `manifest_digest:"v1:<sha256>"`. A logical snapshot can have several physical
locations and branch memberships; all appear. Clients must validate the version,
required fields, identities, cross-references and counts before showing the review.
Both supported WebUIs require review of this list and two distinct confirmations.

`Dataset.RemoveSnapshots` is an administrator-only POST to
`/v7.0/datasets/:dataset_id/remove_snapshots`. Supply the same options and required
`manifest_digest` from the reviewed preview. The server locks the full scope,
rechecks safety and recomputes the inventory before staging any mutation. Changes to history, hierarchy, copy identity, memberships, plans or options
require a new review. An unsupported or stale digest returns the normal failed HaveAPI response
with `errors.manifest_digest:["stale_preview"]`. Clients must use this machine
marker, clear both confirmations and request a new preview explicitly. They must
not replace the digest and submit automatically.

Accepted removal returns the ordinary empty dataset output and
`response._meta.action_state_id`. Submit once and follow the normal task facility.
Closing a client does not cancel work. If the submission outcome is unknown,
inspect existing tasks before deliberately retrying.

## Version 1 inventory

Every key below is required. IDs are positive JSON integers. Nullable fields use
explicit null; timestamps are UTC ISO-8601 strings or null. Counts and history IDs
are nonnegative integers. Names and labels are plain strings and require escaping
when displayed. No download links, secrets or commands are included.

| Array or object | Fields |
| --- | --- |
| Root | `root_dataset_id`, `options:{recursive,disable_plans}`, arrays below, `counts` |
| `datasets` | `id`, nullable `parent_id`, `user_id`, `name`, `full_name`, `current_history_id` |
| `copies` | `id`, `dataset_id`, `pool_id`, `pool_label`, `pool_role`, `pool_filesystem`, Boolean `pool_open`, `node_id`, `node_name` |
| `snapshot_locations` | `snapshot_id`, `snapshot_name`, nullable `snapshot_label`, nullable `created_at`, `history_id`, `dataset_in_pool_id`, `snapshot_in_pool_id`, nullable `snapshot_in_pool_in_branch_id`, nullable `branch_id`, nullable `origin_snapshot_in_pool_in_branch_id` |
| `trees` | `id`, `dataset_in_pool_id`, computed `name`, Boolean `head` |
| `branches` | `id`, `dataset_tree_id`, computed `name`, Boolean `head` |
| `plans` | membership `id`, `dataset_in_pool_id`, `environment_dataset_plan_id`, `dataset_plan_id`, `name`, `action` (`remove` or `retain`) |
| `counts` | `datasets`, `copies`, `snapshots`, `snapshot_locations`, `trees`, `branches`, `plans`, `plans_to_disable` |

`pool_role` is `primary`, `hypervisor` or `backup`. A source snapshot has one
location with null membership, branch and origin IDs. Each backup membership has
one location, with non-null membership and branch IDs. Empty containers still
appear. `snapshots` counts distinct logical IDs; other collection counts match
array lengths. `plans_to_disable` counts `action:remove`. Parent IDs may refer to
an ancestor outside the selected subtree; other links resolve within the arrays.

Rows sort by ID, except locations sort by dataset copy, snapshot, membership
(null sorts as zero), then snapshot copy. Digest input is compact UTF-8 JSON of
`{manifest_version:1,manifest:<complete inventory>}`, with recursively sorted
object keys. Preview time and changing space usage are excluded. The digest is a
concurrency precondition, not an authorization credential or proof of review.

## Safety and recovery

Every included pool and node must be available and outside maintenance, including
closed backup pools. Pending transitions, resource conflicts, mounts, external
clones (including inactive clones), external references, inconsistent ownership,
unsupported automation and invalid branch dependencies reject preparation.
Cleanup does not force unmounts, delete dependent clones or remove ZFS holds.

Locks exclude ordinary snapshot, backup, transfer, restore, clone and plan
operations until the task closes. With the default options, plan unregistration
uses ordinary confirmations and preserves unrelated members of shared snapshot
groups. Backup branches are removed before their origin snapshots, across all
selected trees. Shared snapshot-copy metadata survives until its last membership
is removed. Empty trees and branches are removed too. Source snapshots are last.

All mutation steps are irreversible, including metadata helpers. A construction
failure queues no task and rolls back preparation. A later node failure can leave
partial removal. Successful confirmations remain effective; remaining snapshots
and plans must be assessed from the task and actual node state. Fatal outcomes
retain locks for operator reconciliation. Removing a lock alone does not repair
storage. After reconciling a known failed task, request a fresh preview and retry
the remaining history explicitly. A failed task must never be shown as completed.

Finished snapshot download files remain available under their independent
expiration policy. When the last snapshot copy disappears, metadata references
from both target and base snapshots are cleared; active generation conflicts
through its existing storage locks.

Retained backup destination shells accept a fresh tree and full first transfer
when schedules resume; later transfers can be incremental again. No database
migration, storage format or node command change is required. Deploy compatible
API support before exposing the actions in clients, and complete or reconcile
pending tasks before backend rollback.

Transaction chains retain their class name in the database, including completed
tasks. Every API process that reads this history needs the
`TransactionChains::Dataset::RemoveSnapshots` class. Once a removal chain exists,
a rollback must retain a compatible definition of that class or stay on a
compatible backend. Completing pending tasks alone does not make an older backend
safe. Do not delete or rewrite historical chain rows to enable rollback.

Schema/client synchronization follows [the API export procedure](../api-schema-export.md).
Rollback cannot restore deleted snapshots or removed schedules.
