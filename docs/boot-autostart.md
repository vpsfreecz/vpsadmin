# Boot auto-start obligations

nodectld tracks a fixed cohort from the first complete API inventory durably
accepted before 300 seconds of the current host boot. A background worker captures
the inventory while transactions continue. Transactions completed before capture
can change which VPSes and pools it includes. VPSes arriving after capture do not
join the cohort.

A member remains pending until osctld proves it reached LXC running, or the
supervisor confirms a configuration change that retires the obligation. There is
no upper uptime limit. A fulfilled or retired obligation never rearms during that
boot, including after a restore, swap, migration back, autostart toggle, pool
export/import, or daemon restart.

This describes container startup, not guest application health. The ordinary
`nodectld_vps_autostart_*` metrics remain current-state diagnostics; their meanings
are unchanged. Monitoring rules should use the boot-obligation metrics when
`nodectld_vps_boot_autostart_supported` is 1.

## Enrollment and persistence

The vpsAdminOS nodectld module creates
`/run/nodectl/boot-autostart.json` only in its actual boot hook, before runit.
The directory is root-only and the JSON record has mode 0600. The record uses
schema version 1 and the kernel boot ID. Service startup, configuration activation,
and daemon restart never create a new record.

Monitor construction performs no ledger I/O or RPC. Its initial snapshot is
`unavailable/state_loading`, with no cohort rows, no successful check and a zero
last-success timestamp. The existing background worker loads the ledger on its
first update. Loading state is unknown enrollment state: even after 300 seconds,
a valid same-boot `active` ledger resumes when loading completes. An `enrolling`
ledger loaded at or after the cutoff is rejected before any inventory request.
A ledger-construction failure is terminal `unavailable/state_invalid`; the
monitor does not repeatedly recreate it.

The boot record starts in `enrolling`, with a fixed deadline of 300 seconds since
kernel boot, measured with `CLOCK_BOOTTIME`. The worker requests a complete
[`list_vps_boot_autostart`](boot-autostart-rpc.md) inventory and accepts it only
after validation, persistence and cleanup complete strictly before that deadline.
An empty complete inventory is valid. Missing osctld containers or unimported pools
do not remove VPSes from the API inventory. This snapshot describes API state
during the boot window; transactions before capture can change its membership.

During enrollment, the worker targets a five-second interval between attempts.
It starts another attempt only after the previous one returns. Other checks use
`vps_status_interval`, normally 120 seconds. An ordinary RPC call can spend the
entire window, or wait indefinitely, in setup, retries, recovery or close. The
interval does not limit call duration. Invalid inventory or short failed calls
can be retried while the original window remains; restarting nodectld never
resets the cutoff.

Transactions never deliberately wait for monitoring. The exporter reads an
immutable in-memory snapshot without ledger I/O or the worker lock. When it
observes known enrollment still pending at or after 300 seconds, it reports
unavailable with no actionable rows and permanently rejects that enrollment for
the process lifetime. A delayed worker cannot reactivate it, even by publishing
a stale active result. Timeout persistence waits for the worker without delaying
transactions or the exporter. An already accepted cohort continues to be monitored
after the cutoff. Unknown `state_loading` never installs this enrollment rejection.

The boot-only file records `enrolling`, `active`, or terminal `unavailable`, its
capture deadline and capture time, and each cohort member's frozen ID, pool and
pool filesystem. Pool-filesystem validation matches the supervisor: the root
component starts alphanumeric, later components may begin with `_`, `-` or `.`,
and empty or complete `.`/`..` components are rejected. Obligations transition
atomically from `pending` to `fulfilled` with reason `running`, or `retired` with the authoritative retirement reason.
Writes use a separate mode-0600 file, flush/fsync, and atomic rename. Failed
persistence latches the monitor unavailable; success is never published ahead of
its durable transition. After a detected persistence error, nodectld preserves
failure evidence in `/run/nodectl/boot-autostart.failed.json`, preferably by
renaming the previous ledger. It checks this path before loading normal state;
any sentinel, even malformed or unreadable, latches `persistence_failed` across
restart. An older restored valid ledger cannot clear it. Ordinary successful
writes never clear the sentinel; only actual boot initialization does. If all
filesystem mutations fail, the daemon logs that it could not preserve the latch
across restart. This is a failure record, not a write-ahead or crash journal.
`/run` survives daemon restarts and resets on real reboot.

The running process rejects a candidate if RPC close, validation, persistence or
cleanup returns at or after the deadline. The worker then tries to persist timeout
state or invalidate the candidate without involving the transaction thread.

If rename blocks across the deadline and the process dies after installing the
candidate but before handling the late write, a restart may load that candidate
with its predeadline capture time. That file contains the asynchronous API
snapshot, without durable proof of rename completion time. The design leaves
this window outside its crash guarantees and uses no write-ahead or fencing
journal.

The module also publishes `/etc/nodectl/boot-autostart-version`. The daemon checks
that marker under `/run/booted-system/etc/`, so a live upgrade without enrollment
reports `awaiting_reboot`. A feature-capable boot with a missing record reports
`unavailable/state_missing`. Corrupt, unknown-schema or wrong-boot records are
unavailable evidence; they are never replaced with a fresh inventory.

## Reconciliation

The generic [osctld container-state history](https://github.com/vpsfreecz/vpsadminos/blob/staging/docs/containers/state-history.md)
provides a boot-wide first-running projection through
`osctl -j ct state-history --ever-running`. The projection retains successful
running evidence even after its detailed timeline events are evicted.
It is separate from osctld's autostart scheduler state. The scheduler can mark an
attempt before startup succeeds, so its private `started-cts.txt` is not evidence
for this monitor.

History is matched by `(pool, VPS ID)` and validated against the current boot.
The generic history can also contain unrelated container IDs: 1 to 100 characters
from letters, digits, `_` and `-`, including IDs beginning `_` or `-`. Their
presence does not invalidate numeric VPS history. Pool validation remains
separate from the container-ID alphabet.

A successful observation fulfils its obligation even if the VPS is now stopped,
deleted, or absent, or if supervisor reconciliation fails. Success is persisted
before metrics change. Ordinary present-running samples provide diagnostics and
do not substitute for unavailable history.

Pending IDs are reconciled through
[`reconcile_vps_boot_autostart`](boot-autostart-rpc.md) in batches of up to 1000.
Resource locks and transitional rows retain obligations, including missing rows
with locks or fatal chains. Only complete authoritative retirement responses can
retire obligations. A confirmed change of pool retires the original pool's
obligation without creating a destination obligation. API errors, unknown rows,
omissions and malformed responses retain pending obligations. History success
takes precedence over retirement.

Only the background worker calls the existing `RpcClient.run` lifecycle. Each
inventory request and each pending-ID batch uses its own run, which closes the
reply queue and channel before returning the response for validation. The client
uses ordinary NodeBunny setup, read retries, recovery waits and close behavior.
An RPC or close failure cannot authorize capture or retirement. Proven running
fulfilments are already durable before the worker opens any retirement RPC.

Monitoring adds no deliberate transaction gate or startup ledger I/O. It shares
NodeBunny with other clients, so channel creation, recovery and publish waits can
still delay other callers indirectly. Existing connection setup and unrelated
daemon initialization can also block. This is not a full startup or transaction
latency guarantee.

## Metrics

Every new daemon exports `nodectld_vps_boot_autostart_supported 1` and exactly one
`nodectld_vps_boot_autostart_state{state,reason}` row. States are `enrolling`,
`active`, `awaiting_reboot`, and `unavailable`. The normal enrolling/active reason
is `none`; awaiting reboot uses `not_enrolled`.

Unavailable reasons distinguish enrollment (`enrollment_timeout`,
`inventory_invalid`), local state (`state_loading`, `state_missing`, `state_invalid`,
`boot_id_mismatch`, `persistence_failed`), and dependencies (`osctld_unsupported`,
`osctld_unavailable`, `rpc_unsupported`, `rpc_failed`, `response_invalid`).
Dependency failure changes the exported state without replacing an active ledger;
a later valid check can recover. Lost or unusable local state cannot recapture.

The metric prefix is `nodectld_vps_boot_autostart_`:

| Suffix | Labels | Meaning |
| --- | --- | --- |
| `check_success` | none | Latest complete reconciliation succeeded, 0 or 1 |
| `check_last_success_timestamp_seconds` | none | Unix time of last success, initially 0 |
| `expected` | `pool` | Frozen cohort size including terminal obligations |
| `unsatisfied` | `pool,vps_id` | Pending obligation, value 1 |
| `unsatisfied_reason` | `pool,vps_id,reason` | Pending diagnostic reason, value 1 |
| `unsatisfied_count` | `pool,reason` | Pending count |

Pending diagnostic reasons are `not_running`, `missing`, or `unknown`. They do
not change the VPS identity used by the alert. A complete successful check
requires valid history, pending-ID reconciliation, a local diagnostic query and
successful persistence. Empty and fully terminal cohorts still check provider
health, but need no pending-ID RPC. On failure, the exporter preserves the last
success timestamp and withholds cohort/pending series for that scrape. A blocked
active worker leaves its previous snapshot readable without advancing the success
timestamp; existing freshness checks diagnose stale results. The ledger retains
obligations and may still persist proven fulfilments during API outages.
Boot IDs are never metric labels.

## Upgrade and recovery

Read the [vpsAdminOS compatibility contract](vpsadminos-compatibility.md)
before selecting a node generation or rollback target. The
[upgrade guides](upgrades/README.md) describe supported input transitions and
the recovery semantics they adopt.

Deploy the additive supervisor RPCs first, then osctld history and nodectld/module,
then monitoring rules that use only the boot-obligation metrics. Upgrade node
producers before selecting those rules: nodes without the new metric family have
no per-VPS boot-autostart coverage from them. Missing metrics do not establish
healthy obligations. Each updated node enrolls on its next actual reboot; no
coordinated update of all nodes is required. Nodes with unavailable evidence
must not fall back to stateless alerts. Monitoring grace and debounce delay
alerts without expiring unresolved boot failures.

Older monitoring code ignores the separate boot-monitoring runtime files;
reverting that code can restore the old alert noise. This file compatibility
does not establish support for downgrading osctld. Re-upgrade validates retained
state; it must never reset obligations as a recovery shortcut. Inspect the state/reason,
RPC and history availability, file ownership, boot ID, and node logs when a check
fails. Repair the failing dependency and allow the next check to recover. There
is no daemon-start recapture or automatic repair of lost current-boot evidence.
A real reboot initializes new state; rebooting solely to hide a pending failure
is not a diagnosis or recovery procedure.
