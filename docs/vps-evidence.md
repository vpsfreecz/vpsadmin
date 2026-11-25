# VPS evidence and duration reports

VPS evidence records typed observations about a VPS. The shared duration
evaluator validates the event envelope and accounts for qualified intervals,
rolling windows, current proof and report repeats. Each fixed signal handler
validates its own qualification and measurement semantics and formats report
text. Only `rtnl_latency` with representation `qualified_duration` is currently
supported; unknown signals or representations are rejected. The shared path does
not evaluate arbitrary measurements, snapshots or counters.

## RTNL latency

RTNL exposure accounting counts time when a VPS meets the resource-use and rank
criteria while RTNL responses on its node are slow. These observations identify
a possible contributor, without proving RTNL lock ownership. The detector files
incidents; incident policies separately control warnings and shutdown. Acute
oomd restart and stop handling is unchanged.

## Settings

The SystemConfig category `vps_evidence_rtnl_latency` controls RTNL reporting:

| Setting | Built-in effective default | Supported values |
| --- | --- | --- |
| `enabled` | `false` | boolean |
| `window_seconds` | `86400` | 60 to 604800 |
| `threshold_seconds` | `300` | 1 to `window_seconds` |
| `repeat_seconds` | `86400` | 60 to 604800 |
| `freshness_seconds` | `30` | 5 to 300, greater than the source sampling interval plus 5 seconds |

The numeric SystemConfig overrides default to `null`, which means inherit. The
table shows the effective defaults when neither the site declaration nor a
runtime override supplies a value. Declare site defaults in trusted
`api/config/vps_evidence.rb`:

```ruby
VpsEvidence.configure do
  signal :rtnl_latency,
         window_seconds: 86_400,
         threshold_seconds: 300,
         repeat_seconds: 86_400,
         freshness_seconds: 30
end
```

The declaration supplies only these four numeric defaults for existing signals.
Unknown signals, keys, duplicate declarations and invalid combinations fail
startup. A missing file retains built-in defaults. The file loads before
SystemConfig registration. Each process keeps its loaded defaults until restart.
Deploy the same declaration to API, supervisor and scheduled-task processes,
then restart them.

Site defaults override the built-in defaults. Nonnull runtime SystemConfig
overrides take precedence over both. Clear a numeric override with an empty value in the existing administrator SystemConfig
editor (or null through its API) to inherit again. An existing nonnull value
continues to mask the site value, including one equal to an older default; loading
the file never clears it. Changes to runtime evidence overrides are recorded in
the existing audit log. The settings validator checks the effective window, threshold, repeat period
and freshness together under the existing settings lock.

`enabled` stays a separate runtime switch with effective default false and cannot
be set by the declaration. The RTNL cutoff, qualification predicate, units and
available signals remain source-defined. Incident-count policy limits (3/10),
labels/templates and observe mode remain in the independent incident declaration.
Evidence duration settings determine when credit creates an incident; incident
policies determine how repeated incidents are handled. Node collection has its
own `rtnl_exposure.enable` setting, also false by default.

## Upgrade and rollback

Install backend migration `20261125120000`, event handlers and compatible
templates before enabling node collection. Backend reporting remains disabled
until an administrator enables it. Exposure is unknown for old nodes that do
not send evidence events.
A separate site incident declaration can select codename `rtnl_latency`, source
kind `node_oomd_evidence`, node attribution and source action `none`. Existing
restart/stop-only selectors retain their meaning. See
[incident policies](incident-escalation.md).

For a software rollback, disable collection and reporting and preserve the
ledger, receipts, immutable incident snapshots and interval copies. Removing
the schema destroys that history and is unsuitable for a software rollback.
There is no local spool, new RPC, source-context registration or event
acknowledgement protocol.

## Accepted evidence

The existing node monitor forwards `osctl_oomd_evidence` opts unchanged as a
node-scoped `vps_events` event of type `vps_evidence`. It carries a null VPS ID;
the authenticated receiver validates each target's numeric VPS ID, pool, current
node and owner accounting epoch. All identities are inside opts. The RTNL
handler validates the nested signal context, target qualification evidence and
segment evidence.

Schema 1 uses integer microseconds, positive sequence and part identities, and
bounded typed proofs of the VPS run, resource use and rank. Cgroup identities
may be relative or absolute paths. Validation rejects empty identities, control
characters and `.` or `..` components; accepted paths retain their exact bytes
without normalization. The shared synthetic fixture is
[`vps_evidence_v1.json`](../libnodectld/spec/fixtures/vps_evidence_v1.json).
Each opts object is at most 16 KiB with 16 targets and 16 intervals; a batch has
at most 64 parts. JSON floating-point values are rejected.

For RTNL, only the overlap strictly after a probe's first second is credited. It must lie
inside the linked target qualification window, valid probe coverage and source
sampling interval. Both previous and current target qualification must pass.
The server validates bounds and provenance; rounded resource percentages are
context, not an independent central qualification calculation. The server has
no independent init-PID cache. Fresh typed target proof plus current running
status, node and ownership are required to report.

The receipt identity is authenticated node, signal, producer epoch, sequence
and part. State, advancing cursors, interval union, window expiry and repeats
are isolated by signal. Shared epochs and sequence numbers cannot combine
credit or refresh another signal's proof.
A SHA256 digest of recursively key-sorted parsed opts makes identical replay a
no-op and conflicting reuse an error. Contributions and receipt commit together.
Accepted UTC overlap is unioned per VPS/signal/owner accounting epoch, including
pending/completed overlap, so one microsecond is counted once.

Events older than configured freshness or more than two seconds in the future
are rejected. Original source time determines freshness. Source clocks must
remain consistent within an epoch. New epochs invalidate retained live proofs;
older parts cannot replace newer negative target evidence. Same-owner accepted
intervals survive node/run changes. Former-node input and intervals crossing an
ownership boundary are not credited to the new owner.

## Reports and incomplete coverage

Delivery is best effort through the existing event path. Missing events, parts,
source discontinuities and stale observations leave incomplete coverage. Valid
received parts contribute immediately. Credit is a lower bound: incompleteness
does not prevent reporting at the threshold when fresh evidence confirms that
the VPS still qualifies.
Gaps between intervals do not establish quiet or healthy operation.

The rolling window clips interval endpoints using occurrence time, including
expiration without new events. Pruning removes a live interval only when both
retention periods have expired: its end is older than the configured window plus
freshness, and its acceptance timestamp is older than 24 hours plus 300 seconds.
This preserves daily gains even with a short rolling window. Retention remains
within the maximum seven-day window plus freshness. Enlarging a window beyond
retained history leaves it incomplete. Accepted counters use receipt time
and do not backfill Prometheus occurrence history.

When the score reaches the threshold, vpsAdmin commits the incident, its saved
configuration, score, window, complete interval copies and repeat timestamp in
one transaction. Repeats require the configured period since the last accepted
incident and fresh current proof.
The score does not have to fall below the threshold before another report can
be created. Missed reports are not sent later in a burst. Mail retries use the
same incident. Existing report preferences and incident-policy evaluation still
apply.

Stored report text uses the recipient language and shows the actual settings,
UTC time frames, up to five intervals, and shown/total counts. Optional
`vps_evidence` mail data supplies the saved snapshot, the same preview, omitted
counts and a validated detail URL that requires authentication. Managed external
templates must preserve the stored text and show the detail link. The
`rtnl_latency` codename does not establish a knowledge-base anchor.

The PHP incident detail shows paginated intervals with explicit timezone
offsets. `GET /incident_reports/{id}/evidence_intervals` applies the parent
report's owner and accounting-epoch authorization. Its offset defaults to zero
and its limit to 25 (maximum 100). Each row contains the interval start and end,
credited microseconds, and an optional peak measurement with its unit and
lower-bound flag. The common measurement fields
`measurement`, `peak_unit`, `peak_value` and `peak_is_lower_bound` are nullable
as a group; RTNL always supplies `rtnl_latency` in `microseconds`. The saved
`evidence_snapshot` includes signal, representation and an optional typed
condition (`measurement`, `operator`, `value`, `unit`); RTNL uses
`rtnl_latency > 1000000 microseconds`. The child flattens the condition into
scalar metadata and does not expose raw source evidence. Global metadata
includes the total count and next offset, saved window, settings, score,
completeness and evaluation time. Current configuration changes never rewrite
saved reports. Deploy the API before clients use this additive child resource;
the PHP section checks its capability.

## Current evidence views

`GET /vpses/{vps_id}/evidence` returns every supported signal, including recorded
zero and no-data rows. `GET /vps_evidence` returns only exact positive credit,
including subsecond durations, with optional VPS/signal filters, offset 0 and
limit 25 (maximum 100). Order is signal, descending credited microseconds, then
VPS ID. Members can read their current VPSes; administrators can read all under
the normal VPS lifecycle visibility. Current ownership and accounting epochs are
filtered in SQL before counts and paging, including changes after parent lookup.
Reads never ingest, prune, reconcile or create incidents.

Both views use one UTC read instant and the current configured occurrence window.
Credit remains visible when reporting is disabled or current proof becomes stale
or ineligible, including same-owner history across node/run changes. The API
separates observation freshness, the last source qualification, current reporting
eligibility and whether a report is due. Eligibility requires fresh current proof,
matching placement and VPS status. A report is due only when reporting is also
enabled, credit reaches the threshold and the repeat period has elapsed.

No-data zero means zero recorded credit, without claiming that collection ran or
that the VPS was healthy. Pending ownership transfer or a
state owner/epoch mismatch yields `null` credit and hides prior observations,
incident times and peaks. These rows are excluded from the positive overview. Invalid effective settings
produce null derived scores/window/limits and a sorted `unavailable_signals`
array with `configuration_valid=false`. The array contains selected signal names
with invalid settings, sorted and without duplicates; valid settings produce
`[]`. Missing or stale observations alone do not mean invalid configuration.

Live window settings describe the current configuration; incident details retain
the settings saved at evaluation. Stored qualification and observation times may
remain visible after proof becomes stale. Window completeness describes recorded
coverage and does not by itself establish reporting eligibility. When effective
settings are invalid, observation freshness uses the signal handler default; it
does not validate the configuration.

Peaks use compatible typed measurements from contributing intervals and retain
the lower-bound flag when any contributing observation was pending. Dates retain
microseconds. Member responses omit administrative owner/node references and
never expose raw receipt, target or run data. The PHP views use the existing VPS
detail Evidence action and a positive-credit overview, with timezone-aware dates,
current settings and links to existing incident history. They do not poll or
provide editing controls.

## Daily accepted gains

The existing administrator daily report adds `vps_evidence_gains`; it keeps the
existing recipients, timer and rolling 24-hour period. A gain is a new disjoint
live interval piece accepted in `(from, to]`, measured in integer microseconds.
It is not a rolling-score difference or an occurrence-time total. A late valid
piece counts when it is accepted, preserving its original occurrence endpoints.
Exact duplicates and old overlaps add no gain. Acceptance timestamps commit with
the receipt and ledger and are rolled back with stale or failed ingestion.
Incident copies have no acceptance timestamp and never count as gains.

The report includes every positive aggregate row, grouped by signal, VPS and
original user/accounting epoch. Transfers do not assign old-owner gains to a new
owner. Missing VPS/user records retain numeric identity; optional names and links
refer to current records and do not reconstruct historical labels or placement.
Signal totals include accepted microseconds and the number of aggregate rows.
There is no top-N cut, per-sample list, daily cursor or inferred backfill.

The period and generation time are UTC values rendered with an explicit
recipient timezone. Values describe accepted evidence and can be lower bounds;
rolling-window completeness does not certify daily collection. Gains remain when
incident reporting is disabled. The existing report transaction saves the mail
data once, so retries use the same gains. Independently scheduled or delayed
reports can overlap or leave gaps; the period is not measured from the last successful
email, and there is no exactly-once email or outage catch-up guarantee.

## Metrics

The ordinary central base exporter retains its existing schedule and route.
Per-VPS families use the bounded labels `vps_id` and `signal`:
`vpsadmin_vps_evidence_credit_seconds`,
`vpsadmin_vps_evidence_accepted_seconds_total`,
`vpsadmin_vps_evidence_last_incident_timestamp_seconds`,
`vpsadmin_vps_evidence_report_due`,
`vpsadmin_vps_evidence_observation_age_seconds` and
`vpsadmin_vps_evidence_window_complete`. Unknown observation age is positive
infinity. Configuration gauges `vpsadmin_vps_evidence_window_seconds`,
`vpsadmin_vps_evidence_threshold_seconds`,
`vpsadmin_vps_evidence_repeat_seconds` and
`vpsadmin_vps_evidence_freshness_seconds` use only `signal`.
`vpsadmin_vps_evidence_export_timestamp_seconds` is unlabelled. Only fixed known
signals are exported; run, event, owner and time values are never metric labels.
Owner accounting changes reset the accepted counter's accounting context.
Metrics observe persisted state; they do not drive reporting or preserve history.
