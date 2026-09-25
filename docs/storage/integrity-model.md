# How storage integrity is tracked

vpsAdmin records a logical dataset separately from its copies on ZFS pools.
`Dataset` is the logical object; `DatasetInPool` (DIP) locates a copy.
`Snapshot` is logical history, while `SnapshotInPool` (SIP) locates it on a
DIP. A backup SIP can have several physical branch occurrences, each recorded
as a `SnapshotInPoolInBranch` (SIPB). A SIPB's logical parent is not necessarily
its ZFS origin. [Storage](README.md) describes normal operations and pool
roles; this page explains the evidence kept around those operations.

An API transaction chain prepares catalog rows and locks, then sends commands
to NodeCtld. The node runs each command and saves its result. Confirmations
finish catalog work when the chain closes. A ZFS command can succeed while its
database confirmation fails, or a process can stop after starting a child.
The command status and current catalog alone cannot prove what happened on
disk.

## Admission and scope

`StorageIntegrityScope` identifies a Pool (`pool:<id>`) or DIP (`dip:<id>`).
Its mutation epoch increases when admitted work might change that scope.
`unverified` means the current catalog and disk graph have not been proved to
match. `needs_reconcile` records an unresolved outcome. The `verified` state
exists in the schema, but the current observer writer does not publish it.

The singleton `StorageFreezeControl` row has ID 1, a mode and a monotonic
epoch. Staging a classified chain locks that row in the same SQL transaction
as its catalog and journal writes. An authenticated mode change takes the same
lock and compares the caller's expected epoch. This serializes new admission
with `read_only`. Missing row 1 makes upgraded admission fail closed.

The versioned `StorageEffectRegistry` classifies every transaction handle in
both execute and rollback directions. It answers two distinct questions:

| Decision | Use |
| --- | --- |
| `admission_required` | Whether `read_only` must refuse a new command. This includes configuration, file and download work without a catalog topology effect. |
| Verification impact | Whether an effect can invalidate a scope: `none`, `dependency`, `catalog_identity` or `physical_topology`. Only effectful impact creates an intent. |

A password or file write can require admission without a topology intent.
Snapshot creation has physical impact. Export and property routes can affect
dependencies. Some rollback directions have no storage effect even though
execute does; a harmless rollback does not prove earlier chain members
harmless. The API and NodeCtld maintain paired registries and parity tests.
Unknown handles cannot be treated as safe by inference. This is why the
registry covers VPS, network and general-queue commands as well as commands
whose names start with Dataset.

Old API or node processes and delayed osctld work do not honor the new
admission boundary. A rolling deployment cannot rely on the toggle until
every relevant writer has been accounted for.

## Intent, target and attempt

The journal separates a possible effect from evidence of an actual one:

| Record | Purpose |
| --- | --- |
| `StorageMutationIntent` | Binds a token, command, node, chain and manifest digest to an admitted effect before dispatch. Its phase tracks prepared, running, settled or unresolved work. |
| `StorageMutationIntentScope` | Records each affected scope and its epoch at admission. One command can touch several Pools or DIPs. |
| `StorageMutationTarget` | Orders planned objects and copies known catalog identity, path and owner GUID. An opaque target says the graph is not bounded. |
| `StorageMutationAttempt` | Records one execute or rollback start and its terminal receipt or uncertainty. A retry cannot overwrite the previous attempt. |
| `StorageMutationTargetObservation` | Stores before and after facts for a target, including presence, path, GUID, owner and dependency digests. |

Admission writes the intent, scope links and targets before saving command
input. Production observer commands may be unsigned. A node with receipt
support inserts a started attempt before the effect, then stores observations
and a result. A started attempt without a proved terminal result remains
visible. A failed command can still have changed disk state; compensation
needs its own observation. This is why a single transaction `done` flag cannot
replace the journal.

A nonbackup snapshot command 5204 has a Pool `observer_unbounded` target and
a DIP `snapshot_create` target linked to its SIP. Only the SIP target receives
physical observations. Its production guard may be unsigned, so the receipt
is advisory and supplies no input-authenticity proof. Snapshot names are
allocated under admission as UTC seconds; a busy dataset may receive a name
ahead of wall time. The name is an allocation token, while `created_at` comes
from execution. A test-only opted-in group snapshot 5215 has one Pool observer
target and one SIP target per member, with at most 32 members.
Ordinary production 5215 keeps its existing wire format and opaque observer
evidence. Other opaque effects advance every known Pool scope on the node.
If that set is empty, the intent is unscoped evidence, never a verified scope.

An attempt's nullable strict provenance pair records a registry version and
SHA-256 digest of exact signed input when a test-only strict command starts.
Observer and old-node attempts leave both fields null. A signed guard by
itself cannot promote an observer receipt into strict proof because an old
node may ignore it. Production strict dispatch remains off. Neither strict
test path publishes physical identity or marks a scope verified.

## Catalog identity and observation

SIP and SIPB rows have nullable path, snapshot GUID, owner filesystem GUID,
presence and observation-run fields. A backup SIP is logical; SIPB rows carry
its physical occurrences. GUIDs use `DECIMAL(20,0)` and are not globally
unique. `Pool.zpool_guid` identifies the ZFS pool, which may differ from the
GUID of its managed filesystem root.

`StorageFilesystemIdentity` can represent a Pool root or an owned DIP, tree,
branch or snapshot clone. One catalog owner and one known node/path claim are
allowed. Its ZFS origin may be linked to a SIP/SIPB, absent, unknown or
unresolved. A disk-only object belongs in private observation evidence, not
a fabricated catalog row. Linked origins use restrictive foreign keys.
Publishing them while old writers can destroy their owners risks ZFS success
followed by a rejected DB confirmation. The observer release leaves these
identity and origin links unpublished.

`StorageObservationRun` records a scoped capture window, epoch, collector
version, digest, counts and completion state. A partial or stale run cannot
certify a scope. The [reconciler](integrity-reconciler.md) captures and
compares database and ZFS facts and produces private, non-executable
proposals. Its planner sets `executable: false`; it does not repair database
rows or ZFS. Executable repair needs a separate approval and action journal
bound to the exact plan, signing key, actor and freeze epoch.

## Freeze and drain

The `storage_freeze` API exposes `show`, `read_only`, `read_write` and
`settle_observer`. Each action requires an active administrator's own open
session and API action scope. Mode changes need a reason and the epoch returned
by `show`; the API rechecks actor, session, mode and epoch under SQL locks.
Transition and catch-up audits copy the API user ID, session ID and login.
The WebUI shows status and mode controls to a direct full administrator.

NodeCtld settles generic observer intents when a chain has terminal proof.
During `read_only`, `settle_observer` can inspect bounded pages of old-node
prepared intents. It commits a request audit before the work and a separate
completion audit afterward. An interrupted request can have no completion.
Catch-up checks the epoch per chain, leaves ambiguous work blocked and never
marks a scope verified.

`show` caps blocker counts and ID samples. `db_drained` means relevant database
chains, confirmations, intents, attempts and locks appear quiet at a stable
`read_only` epoch. It does not prove NodeCtld children, ZFS operations or
delayed osctld garbage collection quiet, so `repair_ready` remains false.
Freezing admission, settling the DB, proving node quiet and authorizing a
repair are separate operations.
