# DNS primary transfer readiness

External-zone monitoring describes direct transfer readiness independently of
the secondary's loaded state. Every existing managed secondary and configured
user primary forms one path. Managed peer secondaries remain transfer sources,
but their observations cannot recover a user-primary path.

The node sends the server-zone ID, configured transfer ID and configuration
generation with each result. The supervisor checks the node, current enabled
external zone, existing endpoints, generation and tracking boundary while
holding the server-zone lock followed by the transfer-row lock. Obsolete
results cannot create current state or member-visible path history. Positive
observations win timestamp ties. Raw confirmation rollback is protected by
foreign keys in addition to model callbacks.

An enable transition prepares one generation before node input is captured and
keeps it through repeated validation. Execute and rollback carry their own
tracking pair, including explicit nulls on disable. An asynchronous rollback
restores the original API and persisted node identity together. Cleared derived
readiness may remain pending after rollback; no previous success is recreated.
The restored generation is configured again, while observations from the
replaced generation remain inadmissible. Content recovery still requires the
node's retained full-validation latch.

Administrative source-address changes use one transaction chain. It reserves
the DNS server, then every affected zone in ID order, including pending endpoint
or zone deletion. Direct server-zone creation and whole-zone creation reserve
their selected servers before zones; complete refreshes reserve their zone.
These reservations last until normal completion or completed rollback; fatal
chains retain them for existing recovery procedures. A competing configuration
operation fails with the ordinary resource-lock response before changing data.

After reservation, current SQL rows are materialized in order for configuration
snapshots; pending-destroy transfers and peers are excluded. The changed server
and its peers receive distinct forward/original source maps and matching zone
tracking. Asynchronous rollback can restore the previous source address and
other changed server attributes; the initial API response accepts the queued
operation rather than guaranteeing node success. No cleared readiness is rebuilt.

The administrative action invokes this source-update chain as a root operation.
Its membership discovery view starts after the server reservation, preventing
new joins, and includes all pending associations. The configured product database
uses READ-COMMITTED. REPEATABLE-READ verification uses a fresh root transaction;
an already-stale inherited outer membership snapshot is not a supported caller.
Nested peer refreshes use the parent's reserved IDs and materialized current
snapshots instead of opening another discovery view.

`DnsServerZonePrimaryTransferState` retains the last meaningful status, reason,
failure continuity, evidence source and times. Routine positive checks update
state without creating permanent log rows. Local probe failures and insufficient
cheap recovery advance the observation watermark without claiming readiness.
Access and network failures can recover through IXFR readiness probes; invalid
content or protocol failures require an accepted real transfer or validated AXFR.
See [node probes](dns-transfer-probes.md) for collection and worker isolation.

`evidence_current` requires the current configuration generation and meaningful
evidence within the expected cadence: success is valid for 75 minutes; fast
failures for 15 minutes; invalid-zone, protocol and stale failures for 75 minutes.
Success uses `last_success_at`; failure uses the latest meaningful failure/reason
time. `last_attempt_at` alone is insufficient. Stale or absent evidence counts
pending in `DnsZoneTransfer.transfer_check_*` aggregates without rewriting raw
state or audit. The detail API exposes both the retained status and currentness.
Path pagination uses ascending IDs, matching the API cursor.

Explicit primary failures become alert-eligible after 30 minutes of continuous
evidence; network failures require 24 hours. Gaps beyond the retry window reset
failure continuity. Active incidents require current positive evidence on every
expected path to claim recovery; stopped probes do not close an incident as
healthy. Configuration removal is a separate closure reason. Site monitoring
compares incident path keys with the current endpoint matrix and handles missing
user primaries separately. A detached owned primary remains configured.

`DnsServerZone.zone_status` describes recent local BIND statistics: unknown when
the last check is older than five minutes, not loaded without serial/load time,
expired when expiry has passed, otherwise serving. This does not actively query
an answer, prove user-primary reachability or certify the newest serial is loaded.

Historical pre-cutover log rows use `attempt_kind=legacy` (numeric 6, appended
after the six existing kinds). They retain their contents, event keys, IDs and
latest-attempt pointers; no current primary association or readiness is inferred.
Legacy history retains the previous per-zone member authorization in both list
and show actions. New unbound peer/local diagnostics remain administrator-only.
The node envelope does not accept the legacy kind. Ordinary 365-day log retention
and endpoint deletion policies still apply.

IP cleanup reserves the parent IP then host resources before acquiring ordered
server-zone SQL locks and transfer-row SQL locks. Shared host cleanup must not
eagerly lock transfer rows first. Pending endpoint deletion and path deletion use
the same confirmation graph; failures and rollback retain state and ownership.
See [IP ownership](ip-locking.md) and [UI contracts](dns-transfer-ui.md).
