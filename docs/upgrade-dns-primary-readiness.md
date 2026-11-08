# Upgrade to DNS primary readiness

This procedure describes the coordinated protocol transition. It is not a
deployment receipt. The API, supervisor, DNS node scheduler/worker/unit settings,
site monitor configuration, templates and clients must be prepared together.
The old and new node configuration/event envelopes cannot be mixed.

Core migration `20261108120000` follows the current core schema. It adds tracking
generations and path state, marks existing transfer logs as legacy, and preserves
their exact contents and cached latest-attempt fields. It refuses orphan audit
rows or invalid latest pointers before DDL, reporting IDs for operator
reconciliation. Do not delete audit or guess associations to make it proceed.
New path state starts unknown until matching observations arrive.

Monitoring migration `20261108121000` closes only active legacy
`dns_secondary_transfer_failure` events on `DnsServerZone` and appends a state
and serialized observation with reason `superseded_by_primary_readiness` and
replacement monitor `dns_primary_transfer_failure`. It preserves IDs, prior
state/observations, alert counts and last-report times; it sends no mail. The new
readiness and missing-primary monitors use separate names. Ignored incidents
retain the framework's ordinary ignored behavior in subsequent monitoring.

Before cutover, prepare a backup and exact old/new package/configuration inputs,
queue inventories and rollback packages. Verify synchronized clocks. Stop
monitoring and drain outstanding alert/mail work, then stop DNS configuration
writers. Keep old nodes available to drain old configuration transactions and
require `rake vpsadmin:dns:verify_configuration_drained` to report zero.

Stop every old DNS nodectld producer, drain transfer events using matching old
supervisors, then stop consumers and remaining monitoring writers. Apply the
additive API/plugin migrations at this empty boundary. Run:

```sh
CONFIRM=1 bundle exec rake vpsadmin:dns:reset_primary_transfer_tracking
```

Initialization queues one reserved chain per zone with nested peer refreshes,
while reporting the number of server-zone updates. If enqueueing fails after
the tracking reset committed, keep writers, consumers and monitoring stopped.
Reconcile and drain any already-queued matching-version configuration before
rerunning the reset; do not rotate generations over pending snapshots. Each
refresh's rollback returns to its initialized snapshot, not pre-reset state.

The initializer clears derived path state, rotates enabled external-zone
generations and queues complete server-zone configuration refreshes. It preserves
all transfer audit and latest-attempt fields and normalizes rollback-era rows
with null attempt kind to legacy. Start matching new nodes, verify queued full
configuration refreshes and persisted envelopes, then start only new consumers.
Drain and inspect new events before resuming API writers and monitoring. Check
direct user-primary paths, peer isolation, serving state, current evidence,
missing-primary conditions and ordinary recovery/configuration-removal messages.

For software rollback, stop writers/monitoring, leave new nodes available to
drain new-format configuration transactions, and require:

```sh
bundle exec rake vpsadmin:dns:verify_primary_transfer_configuration_drained
```

Stop new producers, drain with matching consumers, then stop consumers. Retain
the additive schema; do not run migration down, which refuses to discard new
audit. At the drained boundary use `CONFIRM=1 REFRESH_CONFIGURATION=0` with the
initializer to invalidate derived tracking without delivering new configuration
to old nodes. Restore matching old node/API/configuration/monitor packages and
their old-format configuration under the same writer/queue barriers. Retain
journal cursors and reconcile unfinished transactions before restart; never
replay old configuration into the wrong node version.

A later re-upgrade repeats the drained transition and safe initializer. With
monitoring writers stopped and alert work drained, retire any rollback-era legacy
incidents explicitly:

```sh
CONFIRM=1 bundle exec rake vpsadmin:monitoring:supersede_legacy_dns_transfer_events
```

The guarded task rechecks active old-name server-zone events under row locks,
appends the same supersession audit and closes them without mail. Repeating it
does not duplicate observations or change already-retired IDs. The one-time
plugin migration stays self-contained and is not manually rerun. No scheduled
runtime command invokes supersession. Null
rollback-era log kinds become legacy without rewriting their evidence. It does
not reopen superseded incidents or delete current audit. Preserve exact source,
schema, client export and generation receipts for each transition. The archived
prototype's `20260813120000`/`20260813121000` destructive migrations were consumed
only in recorded disposable development work and must not replace these versions.
