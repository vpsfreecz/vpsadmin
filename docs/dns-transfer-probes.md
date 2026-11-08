# DNS transfer collection and active probes

DNS nodes report two independent observations: local BIND serving state and
transfer readiness for every configured user primary. A loaded secondary can
serve a zone obtained from another managed secondary while every user primary
is unreachable. Equal serials between secondaries do not prove direct access to
a primary or that the loaded content is its latest content.

## Collection and path identity

[`DnsStatus`](../libnodectld/lib/nodectld/dns_status.rb) reads local BIND statistics
and supplies the loaded serial to the probe coordinator. Serving state describes
that local observation; it is not an active authoritative-answer check.

[`DnsTransferLog`](../libnodectld/lib/nodectld/dns_transfer_log.rb) follows the
configured BIND journal identifiers. It correlates connection, rejection and
terminal messages using BIND's transfer pointer, with zone/address fallback for
older log forms. A reused pointer starts a new attempt. Correlation is bounded
to 256 attempts and 130 minutes, slightly longer than BIND's default incoming
transfer time limit. The durable journal cursor stays behind unresolved managed
attempts so a restart can rebuild their association. Publication precedes cursor
advancement; replay deduplicates by the journal-derived event key.

A terminal `success` or a completion summary alone does not prove that BIND
accepted zone content. The parser waits for an associated transferred serial or
zone rejection. This prevents a failed, zero-record transfer summary from
clearing the failure. An explicit up-to-date refresh or NOTIFY is narrower
positive evidence and retains its own attempt kind.

The API supplies the managed server-zone ID, each user-primary transfer ID,
configuration generation, tracking boundary and family-specific source addresses
in node configuration. Primaries are marked `user_primary` or `vpsadmin_peer`.
Both log and probe producers include the managed IDs and opaque generation in
their `dns_transfer_logs` events. The log parser snapshots these values when the
attempt starts, rather than associating an old completion with a replacement
configuration. The API consumer remains responsible for admitting only current,
authorized endpoints and generations.

## What an active check establishes

[`DnsTransferProbe`](../libnodectld/lib/nodectld/dns_transfer_probe.rb) schedules
every enabled external secondary zone × user-primary path. Peer secondaries are
excluded. It binds queries to the same address family and configured transfer
source as BIND and uses the path's TSIG key when present. Missing source addresses
are reported as local failures; the worker does not fall back to another source.

With a known loaded serial, the worker first requests authoritative SOA, then
TCP `IXFR=<primary serial>` from that same primary. A valid authoritative single
SOA reply confirms direct transfer readiness even if the serial has not changed.
A serial behind the loaded secondary is `stale`, using DNS serial arithmetic.
A primary ahead of the secondary can pass this check: readiness does not claim
that BIND has loaded the newer content. Reloads, peer success, elapsed time and
local timer changes do not synthesize primary recovery.

Without a loaded serial, when IXFR is unsupported or does not yield a suitable
single-SOA reply, or when full validation is required, the worker fetches AXFR
and validates the result with stock BIND `named-checkconf -z`. Content/protocol
failures latch a full-validation requirement. The coordinator persists that
requirement before publishing the failure, retains it across daemon restarts
and generation changes for the same endpoint IDs, and clears it after successful
AXFR validation. A cheap IXFR result cannot clear the consumer's content-failure
state; accepted real BIND transfers can also supply full recovery evidence.

Paths are keyed by server-zone ID, transfer ID and generation. Removing a path
or rotating its generation cancels its running service, removes scheduled work
and discards late results. Persistent latch entries disappear when the endpoint
itself disappears. Disabling a zone cancels its checks but retains the latch,
including across daemon restarts, so re-enabling still requires full validation.
Keeping an owned IP's DNS reference during detachment preserves
its endpoint identity and checks; detachment alone is not a transfer result.

## Worker boundary and limits

The coordinator owns configuration and RabbitMQ publication.
[`DnsTransferProbeRunner`](../libnodectld/lib/nodectld/dns_transfer_probe_runner.rb)
starts one transient systemd service per check. The
[`worker`](../libnodectld/lib/nodectld/dns_transfer_probe_worker.rb) receives only
the selected zone, primary/source addresses, optional TSIG, loaded serial and
check limits over stdin. It receives no broker credentials, managed endpoint IDs
or generation. Its bounded JSON result is schema-checked before publication.
The packaged executable is `vpsadmin-dns-transfer-probe`; the NixOS module selects
absolute worker, systemd and BIND command paths.

Each service uses a non-root dynamic user, a private temporary directory,
`NoNewPrivileges`, an empty capability set and filesystem/kernel protections.
It cannot access `/var/named`, `/var/lib/nodectld` or `/etc/vpsadmin`. Network
access is denied except to the selected primary, with only IPv4/IPv6 families
allowed. TSIG files are mode 0600 temporary files. Queries use stdin instead of
putting key contents or query data in command arguments. Worker errors do not
echo rejected job contents. Service resources are limited to 768 MiB, 16 tasks
and 64 file descriptors; the service is part of `vpsadmin-nodectld.service`.

The `dns_server` settings have these defaults:

| Setting | Default |
| --- | --- |
| `transfer_probe_interval` | 1 hour after a conclusive slow/healthy check |
| `transfer_probe_failure_interval` | 5 minutes for network/access failures |
| `transfer_probe_concurrency` | 5 services |
| `transfer_probe_timeout` | 30 seconds per ordinary probe command |
| `transfer_probe_axfr_timeout` | 10 minutes |
| `transfer_probe_axfr_max_bytes` | 256 MiB |
| `transfer_probe_state_file` | `/var/lib/nodectld/dns-transfer-probe.json` |

New paths are deterministically staggered over the first 60 seconds. Relevant
BIND failures request an immediate check, including a full check for content or
protocol errors. The runner bounds captured output to 128 KiB and validates
64 KiB job/result envelopes; individual diagnostic text is capped at 2048 bytes.
AXFR validation has its own 60-second limit. Service runtime includes both
ordinary queries, AXFR and validation allowance. Hitting local resource/command
limits is inconclusive local evidence, not proof of a broken primary.

Check timestamps remain visible. The API derives evidence currentness and
pending aggregates from meaningful success/failure evidence and the current
generation. The node does not turn stale observations into success or rewrite
historical outcomes when a check stops running.

## Coordinated upgrade and recovery

This configuration/event format requires matching API consumers and node
producers. Deploy the scheduler, worker, package executable and NixOS settings
together; new configuration must not be sent to old nodectld. Clock
synchronization is required for event admission and evidence ages. No vpsAdminOS
change is required.

The coordinated boundary stops configuration writers, drains outstanding
transactions using old nodes, stops old producers and drains their events with
matching consumers. Consumers and monitor writers then stop before the prepared
additive migration and readiness initialization. Refresh all affected node
configurations before starting matching producers/consumers and resuming writes.
Initialization preserves historical audit and begins new readiness as unknown.
Site rollout procedures must specify exact versions, queues and outstanding
transactions before executing this sequence.

Rollback also needs matching configuration and event drains in reverse order.
Retain the additive schema and audit; restoring old software does not permit
replaying new-format events into old consumers or guessing endpoint associations.
Preserve the journal cursor and persistent validation latch with their matching
node configuration. Do not advance a cursor to hide unresolved attempts or
delete the latch to manufacture recovery. Operational initialization, cursor
recovery and database rollback belong to the prepared API/site upgrade procedure.
