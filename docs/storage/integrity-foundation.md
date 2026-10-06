# Storage integrity schema

[How storage integrity is tracked](integrity-model.md) explains the writer,
freeze and reconciliation flow. This page records the catalog constraints that
matter when inspecting the database or extending that flow.

## Logical rows and physical occurrence

`Snapshot` is logical history. `SnapshotInPool` (SIP) places it on one
`DatasetInPool` (DIP). A nonbackup SIP can carry the physical snapshot path,
GUID, owner filesystem GUID, presence and observation-run ID. On a backup pool,
the SIP remains logical and each `SnapshotInPoolInBranch` (SIPB) carries those
fields for a branch occurrence. The model rejects physical fields on a backup
SIP. SIPB logical parent pointers do not identify ZFS clone origins.

GUID columns use `DECIMAL(20,0)`. A received snapshot can keep the same GUID
on more than one filesystem, so GUID alone is not a unique object key.
`Pool.zpool_guid` identifies the containing ZFS pool; it may differ from the
GUID of the managed filesystem at `Pool.filesystem`.

A `StorageFilesystemIdentity` row represents a managed Pool root, DIP, tree,
branch or snapshot clone. Exactly one catalog owner key belongs on a row.
The owner ID remains copied when a live FK clears. A unique owner index
prevents two identities for the same catalog object. For a known path, the
unique `(node_id, path_digest)` claim prevents two identities from claiming
one node path. The application derives the SHA-256 digest from exact path
bytes and compares full paths on a digest match. Path collation is binary.
An unknown path remains null rather than being guessed.

`origin_state` distinguishes unknown, no origin, linked and unresolved. Only
a linked state carries exactly one SIP or SIPB origin FK. Unknown disk-only
objects belong in private inventory evidence, not a synthetic catalog owner.
The linked-origin FKs restrict deletion. Publishing these rows while an old
writer can destroy their owners could leave a successful ZFS operation with a
rejected database confirmation. The current observer release does not publish
catalog-owned filesystem identities or SIP/SIPB physical links.

MariaDB cannot use a CHECK referencing an FK column. The database retains
real FKs, unique owner/path indexes and scalar CHECKs; the model enforces
cross-FK owner and catalog-ID rules. A direct SQL writer can bypass model
validations. A future guarded writer must use checked writes and a complete
reconciliation must audit these relationships before calling a scope verified.

## Audit and receipt constraints

`StorageIntegrityScope` keys are `pool:<id>` and `dip:<id>`, with copied
catalog IDs, a mutation epoch and a state. The initial schema creates no
scopes. An intent's scope link copies the expected epoch so a later observer
can detect intervening admitted work. Targets carry sequence numbers and
copied catalog identity. A target can link to at most one live catalog object;
its copied kind and ID survive removal of that link.

Each attempt has one direction and attempt number. The started row may receive
one terminal receipt and target observations; application models refuse later
changes to a finished receipt. The nullable strict registry version and
signed-input digest must be present together and cannot be added by a model
update after the attempt starts. Old and observer attempts leave them null.
The database CHECK enforces the pair shape; the application enforces the
stronger update rule. These fields are evidence of test-only strict dispatch,
not authorization to run it in production.

`StorageFreezeControl` is a singleton with ID 1. An upgrade migration inserts
it for an existing database; a fresh schema load uses the explicit bootstrap
task before the setup marker is written. The task does not run on an
initialized database. Admission looks up row 1 and fails closed if it is
missing. Transition and catch-up audit rows copy the acting API user ID,
session ID and login. They have no cascading user/session FKs, so account
removal cannot erase historical actor identity. Audit writes are append-only
through the application, not tamper-proof against privileged SQL.

`StorageObservationRun` stores capture windows, scope epoch, collector
version, digest, counts and completion state. An interrupted or stale run
cannot certify a scope. There is no executable reconciliation decision or
action table in the current schema. The private planner's candidates cannot
be applied until an approval and action journal with exact evidence, actor,
key and freeze-epoch binding is implemented.

## API maintenance reservations

`StorageMaintenanceRun` retains an API reservation and its audit.
`StorageFreezeControl.active_maintenance_run_id` is the single active owner
pointer. Its unique index and restrictive FK prevent deletion of a referenced
run. An existing installation starts with a null pointer and no run; provider
state never creates API ownership.

Record contract 1 has two states: `reserved` at revision 1 and `abandoned` at
revision 2. Its requested profile is `manual_storage_only_v1`. Acquisition
records a canonical client UUID, freeze epoch, requested catalog scope and
SHA-256 digest, plus the locked administrator's user/session IDs, copied login,
reason and time. The scope is canonical JSON of 1 to 256 distinct Pool claims
in ID order, bounded to 1 MiB. Each claim copies Pool/node IDs, Pool role/filesystem, Node role and
hypervisor type, and known catalog zpool GUID or null. These claims describe
the requested catalog; they do not identify a physical dependency closure.
Aliases and absent GUIDs remain unproved.

The model keeps acquisition fields immutable. Its only supported update adds
the abandoning administrator's separately copied identity, reason and time,
changes state and advances revision. Database constraints enforce complete
acquisition and terminal audit groups, state/revision pairs, JSON size/validity
and UUID uniqueness. User/session and catalog identities are copied rather
than cascading FKs. Privileged SQL can bypass model immutability; this schema
is not a tamper-proof audit journal. Completed runs remain retained.

The additive reservation migration preserves the existing singleton mode,
epoch and freeze audit. Its down migration checks for any run or active
pointer before DDL and refuses to discard consumed audit. Keep the additive
schema on code rollback once a reservation has existed. Unknown record
contracts, malformed scope or inconsistent ownership fail closed in supported
reservation readers. A future physical handoff must change the recognized
contract before accepting its first physical responsibility or evidence;
contract 1 cannot represent that handoff.
