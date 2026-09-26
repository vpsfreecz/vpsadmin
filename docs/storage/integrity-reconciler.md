# Storage integrity observer capture

The first reconciler stage records one database snapshot and two read-only ZFS
inventories, then compares them offline. It cannot approve or apply a repair.
Its reports are advisory while older storage writers and osctld runtime dataset
work can still operate. A complete report says the capture protocol completed;
it does not certify a scope or make a snapshot safe to delete.

## Operator interface

Run the installed script through `vpsadmin-supervisor-ruby` from an authorized
interactive shell. That wrapper resolves the script path before switching to
the Supervisor service user and package working directory. Use an absolute
private directory writable by that service user. Set its owner to the configured
Supervisor user and group and its mode to `0700`; the files are `0600`.
For example, prepare `/var/lib/vpsadmin-storage-reconciler` with `install -d`
using the actual Supervisor service account, then run:

```sh
vpsadmin-supervisor-ruby /path/to/api/bin/vpsadmin-storage-reconcile \
  capture --pool-id 123 --mode bootstrap \
  --private-dir /var/lib/vpsadmin-storage-reconciler
vpsadmin-supervisor-ruby /path/to/api/bin/vpsadmin-storage-reconcile \
  compare --run-id 456 --private-dir /var/lib/vpsadmin-storage-reconciler
vpsadmin-supervisor-ruby /path/to/api/bin/vpsadmin-storage-reconcile \
  dry-run --run-id 456 --private-dir /var/lib/vpsadmin-storage-reconciler
vpsadmin-supervisor-ruby /path/to/api/bin/vpsadmin-storage-reconcile \
  plan --run-id 456 --private-dir /var/lib/vpsadmin-storage-reconciler
vpsadmin-supervisor-ruby /path/to/api/bin/vpsadmin-storage-reconcile \
  activity-report --private-dir /var/lib/vpsadmin-storage-reconciler
```

These are interface examples, not a production runbook. The capture command
requires a controlling TTY and prompts without echo for the existing
transaction-key passphrase. It unlocks the signer in that one process and
checks an actual signature. The passphrase is not accepted through arguments,
environment variables or files. The CLI reads RabbitMQ connection fields from
the protected `config/supervisor.yml` through
`VpsAdmin::Supervisor::Cli.parse_config`, opens Bunny directly, then declares,
binds and starts its unique durable manual-ACK queue before enqueuing a signed
read-only NodeCtld transaction. Broker ACL failure, missing signing-key DB
grant, a locked signer, an old node handle or a lost queue stops capture.
The 5290 transaction persists the established `storage` queue name. Upgraded
NodeCtld routes that handle to its dedicated `inventory` worker; an older
daemon can still receive the known queue and reject the unsupported handle.
The CLI detects that terminal failure while waiting for inventory frames and
leaves the attempt incomplete.
`compare`, `dry-run` and `plan` load only the artifact reader and planner.
Even in a cold process they do not boot the API, access the database or
RabbitMQ, or unlock the transaction signer.

`activity-report` is a separate sampled observation while the global freeze is
`read_only` and DB-drained. It signs one handle 5291 probe for each node with
managed Pools, captures every Pool with the existing two-pass inventory, then
checks the DB and probes again. The probe keeps the persisted `storage` queue
for old-node compatibility; an upgraded node runs it on `inventory`. Each
probe verifies the signed node, epoch and complete Pool claims against its DB
and reads `pool_storage_activity` through a bounded local osctld socket. An old
node or osctld, a missing Pool, changed epoch or generation, or incomplete
inventory leaves the report unknown. Multiple managed roots on one zpool remain
separate Pool claims, with one osctld read for that zpool per probe.
The full observation has a four-hour monotonic deadline. An expired interval
produces a private unknown report and needs a fresh attempt. Normal probe
output binds the signed request by digest and carries Pool IDs and zpool names,
without repeating managed-root paths.

The command writes `activity-UUID/report.json` and its captures under a private
`activity-UUID/captures` directory. The report contains IDs, counts and daemon
generations, without member paths. It always exits `2`: the current NodeCtld
observer cannot prove every child lifetime, so even a stable sampled interval
does not establish `node_quiet`, `repair_ready` or repair authority. A sample
does not prevent later work. Deploy the osctld activity interface and the
NodeCtld observer before using 5291; a mixed-version response remains unknown.
The paired effect registry version is 5. Strict dispatch is still test-only;
its signed guard version must match the upgraded API and NodeCtld during tests.

Exit `0` means a complete advisory report even when it contains findings.
Exit `2` means incomplete or stale evidence; exit `3` means invalid input or
unsupported artifacts. The CLI prints only a run ID, state or finding count.
Inspect the private manifest and report for details.

## Private evidence and replay

The directory is a persistent root with `run-ID` subdirectories. The first
capture creates one random 32-byte `finding-key.bin` under an empty root with
exclusive creation, mode `0600`, and file and directory fsync. A missing key
after any run, a symlink, wrong owner or unsafe mode is an error. Restore the
matching protected backup or explicitly establish a later key epoch and
recapture; compare never generates a replacement. The private manifest stores
only the first 128 bits of the key's SHA-256 fingerprint, the HMAC algorithm
and canonicalization version. Unknown disk paths and the raw key stay out of
the database, transaction input, logs and shareable summaries. An opaque disk
finding key binds the node, zpool, exact path, object type and GUID.
Clone-edge keys and evidence digests also use this private HMAC key when exact
physical paths participate; no unkeyed digest of an unknown path becomes a
finding identity.

`db.jsonl` is atomically published only after its single repeatable-read,
read-only DB transaction commits. It uses API model relations, 1,000-row
primary-key pages, a 15-minute wall limit, 10-second statement limit and
300,000-row cap. It also caps visited rows at 300,000 and the DB artifact at
1 GiB. A failed required query or exceeded cap leaves no published DB file.
Server UTC time and connection ID delimit the snapshot.
Captured storage GUID and owner GUID DECIMAL fields are written as plain
unsigned decimal strings and must fit within 64 bits. An invalid value stops
the capture; other DECIMAL fields retain their normal model serialization.
Recapture artifacts made before this normalization before relying on exact
GUID comparisons; replay does not rewrite their recorded values.
The JSONL includes relevant cross-pool SIPB parent and inbound clone rows. For
the selected catalog it follows every pending SIP or SIPB target through live
and copied catalog IDs, then includes sibling targets, attempts and
observations. It also captures observable work on the selected node and the
complete membership of reached chains. It does not enumerate all settled
intents or completed rollback transactions from the node's lifetime.
`TransactionConfirmation.row_pks` is YAML without an index. For unrelated
pending confirmations in a reached chain, the capture keeps status and chain
metadata but omits row keys and attribute changes. Completed confirmations
outside selected catalog rows are not claimed as captured. A missing
historical confirmation is never proof of absence. Findings for pending
Datasets, DB-only Branches and detached heads retain that blocker.

A finished rollback clears the DB chain-overlap blocker only when the captured
chain has every member (at most 256), terminal results and a finish time for
each member. Each result is limited to 128 KiB. A skipped member must never
have started. Missing, oversized or contradictory results leave the capture
stale; transaction payloads are checked
in memory and omitted from `db.jsonl`. This proves DB chain completion, not
physical quiet.

The node lists the whole named zpool twice, sorted by exact path. Each pass
has a signed two-hour wall deadline, including a silent `zfs list` subprocess
and Rabbit publisher confirmation; an overdue subprocess is terminated and
reaped. Each immutable message carries a run/attempt, sequence, counts and
digest. The CLI fsyncs records, then an exact contiguous checkpoint, then
ACKs the broker. It accepts an exact replay within the live receiver and
rejects a changed replay or gap. A CLI crash leaves that attempt incomplete;
the next capture creates a new DB run and new signed UUIDs rather than
reopening the partial spool. The final marker is ACKed only after a local
seal; a separate complete manifest follows a matching
successful signed transaction result. An incomplete spool without that
manifest cannot be compared. No reverse application-ACK route exists.

Offline `compare`, `dry-run` and `plan` may be repeated for the same complete capture.
They accept an existing output only when its bytes match recomputed output,
and can finish a missing summary after checking the preceding JSONL file.
A changed or tampered output fails closed; an incomplete file pair is not a
complete report.

The capture writer seals manifest version 2 with source policy 2 and JSONL
record version 1. Its evidence selection covers the selected catalog, pending
snapshot evidence and observable work on the selected node. Historical
terminal coverage remains unknown. The offline reader also accepts sealed
version 1, policy 1 captures: it verifies their original bytes and derives an
in-memory view with unspecified selectors and unknown historical coverage.
It does not rewrite the capture. Other version and policy pairs are rejected.
An older reader that accepts only version 1 needs an older capture; it cannot
read a version 2 manifest after a software rollback.

The scanner currently caps a zpool at 200,000 objects and the receiver's
durable queue at 256 MiB with reject-on-overflow and four-hour expiry.
Exceeding a bound, unsupported ZFS properties, unclosed origin/clone edges,
volatile passes, a different GUID/root, missed result or epoch overlap yields
incomplete or stale evidence. A 22-minute production backup scan motivated
the two-hour signed deadline; an operator must still check the node's current
load and Rabbit capacity before any live capture. No production capture has
been run for this slice.

## Advisory comparison

The matcher keeps exact paths only in restricted private output. It reports
reciprocal clone-origin pairs once, unknown disk objects without importing
them, DB-only Branches, reference-count differences for selected-pool SIPs
with captured reverse closure, unresolved SIPB parents,
pending Dataset creates and headless backup DIPs. It checks branch-head
cardinality only on head trees. A headless backup DIP may be intentionally
detached; a completed historical detachment is not inferred from missing
selected-chain confirmations. A reference-count surplus is diagnostic even
with cross-pool rows present, and pending references cannot establish a firm
minimum. The four exact Pool::Create support filesystems under
`<Pool.filesystem>/vpsadmin` are recognized as structural; unexpected children
and snapshots remain visible. A pending Snapshot name may retain
` (unconfirmed)` while its physical name does not. An exact captured 5204
intent and target permit an unresolved correlation; without that binding the
report shows a possible pair with the physical object still unidentified.
The current DB artifact omits signed transaction input, and fatal or unsettled
attempts cannot prove identity or authorize backfill. `compare` writes
`findings-v2.jsonl` and `report-v2.json`, recording the source manifest pair,
effective coverage and its digest. The unknown historical coverage and
unproved legacy selection remain blockers. `dry-run` writes separate
`advisory-actions-v2.jsonl` and `advisory-dry-run-v2.json` no-action files.
`plan` uses the same offline proof policy and writes
`candidate-actions-v3.jsonl` and `dry-run-v3.json`; the separate names preserve
earlier plan version 2 files. It checks the sealed capture, recomputes the
comparison, then requires the policy 2 findings and report to match exactly.
A missing, changed or stale input stops planning. Both commands can finish an
interrupted summary only after the preceding JSONL matches the recomputed
bytes.

Each v3 action binds the run, finding, evidence, capture, report, key epoch and
plan policy with a private HMAC. A unique snapshot path, type, GUID and owning
filesystem GUID can yield a blocked SIP or SIPB identity backfill candidate.
A uniquely matched Pool root, DIP, Tree, Branch or persistent clone can yield a
blocked filesystem identity insert or backfill candidate. These require a
complete two-pass scan, one catalog owner and no unsettled node mutation. The
four exact Pool support filesystems and disk-only objects never become catalog
insert candidates. The DB capture includes identities for the selected Pool
and its dependency closure, not every identity on the node. Filesystem identity
inserts and physical origin candidates therefore carry a full-node claim
blocker. Their preconditions require a later locked full-DB check for another
owner FK claimant and another identity with the same node and raw path or path
digest. An existing identity is excluded from those negative checks and bound
to its captured row. The offline planner does not run these full-DB checks.

An exact reciprocal clone edge can yield a blocked physical origin candidate.
It depends on separate owner or snapshot identity candidates when those fields
are unpublished. A populated source occurrence also needs an exact matching
filesystem owner identity or its own blocked backfill dependency; a conflicting
owner GUID or Pool prevents an origin candidate. Physical origin and logical
SIPB parent are independent;
the planner never proposes a SIPB parent edit from ZFS origin. Every candidate
still needs a fresh frozen graph and strict writer coverage before approval or
application. Empty branches, reference-count differences, unresolved parents,
pending Datasets and headless backup DIPs remain no-action findings without
their missing proofs. All v3 records have `executable: false`; the planner
writes no database rows and calls no node.

The authenticated storage-freeze API and WebUI expose a bounded database
drain status. Existing admitted chains may still settle, and the status does
not prove NodeCtld children or delayed osctld work quiet. VPS start/stop and
other opaque effects need guarded coverage before a frozen repair can be
claimed ready. No scope is marked `verified` by this observer command.
