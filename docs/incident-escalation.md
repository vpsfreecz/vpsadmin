# Incident escalation

vpsAdmin applies shared escalation to explicitly registered incident types.
The initial `oomd` type represents VPS memory-pressure incidents from successful
whole-VPS daemon interventions. It is separate from ordinary process OOM reports.
An incident codename alone does not enroll reports in escalation. The default
thresholds are five
incidents in the last seven days for a warning and ten in the last thirty days
for an automatic stop. Windows use UTC durations and original event times, with
an open lower boundary and a closed upper boundary.

A new incident can cause a stop when the monthly threshold is reached. Further
stops require an incident occurring at least 24 hours after the last confirmed
stop. Manual starts remain available. Incidents during cooldown count toward the
limits but never schedule a later stop. Falling below the monthly threshold
restores the ordinary threshold rules. Warnings recur at most once in seven days
and a stop supersedes a warning due for the same incident.

## Settings and summaries

The `incident_policy_oomd` SystemConfig category has administrator-only `mode`,
`warning_limit`, and `stop_limit` settings. Modes are `observe` (counts only,
the default), `notify` (also threshold warnings), and `enforce` (also automatic
stops). Each VPS/type policy has nullable `incident_warning_limit_override` and
`incident_stop_limit_override` values. Null inherits the registered type’s global limit. Both effective
limits must be positive, and the stop limit must be at least the warning limit.
Invalid stored settings disable automatic actions and report a diagnostic.

`incident_enforcement_enabled=false` exempts a VPS from these automatic stops. It
preserves incident collection and warnings, and does not disable the node's OOM
daemon. An exemption cannot cancel a stop that has already been dispatched.
Changing settings or mode alone never initiates an action.

The existing VPS Index and Show API accept a registered `incident_policy`,
defaulting to `oomd` on reads, and return its localized `incident_policy_label`
and server-calculated `incident_*` summaries:
rolling counts and effective limits, mode and exemption, threshold status,
last incident, last queued warning, last confirmed stop, cooldown boundary and
outstanding stop chain state. Index accepts selected-type `incident_status` and
`incident_enforcement_enabled` filters before pagination. Counts, thresholds and warning recurrence belong to the selected type. Stop
permission, ownership epoch, cooldown and outstanding physical stop are shared
across types for the VPS. The statuses are `clear`,
`near_limit` (at least 80% of either limit), `warning`, and `stop_threshold`, in
increasing precedence. Status depends on counts; mode, exemptions and outstanding
actions are separate. List counts use one request time and batched queries.

Owners can read summaries. Only administrators can read raw overrides or change
the three VPS settings through the existing Update route. Sending explicit null
resets an override; omitting it preserves its value. Settings-only updates use
the existing synchronous acknowledgment without a transaction-chain receipt.
Writes require an explicit registered `incident_policy` and at least one
setting. Unknown, blank or null selectors fail; selector-only writes fail.
Send incident settings separately from other VPS changes. Mixed requests are rejected
before effects, keeping validation and audit synchronous. The existing audit records both per-type overrides and shared stop permission
changes. Both WebUIs use these fields and hide the
feature when an older API lacks a numeric `incident_count_7d` together with
`incident_policy`. Missing capability is unavailable, not zero.

## Event and ownership boundaries

Each code-defined `IncidentEscalation::RULES` entry supplies its qualification
relation, labels, configuration category and optional specific template pair.
Only trusted `node_vps_event` provenance with source identity, source node,
`restart`/`stop` action and `oomd` codename qualifies for the initial rule.
Source node records ingestion-time ownership; later VPS migration preserves
historical qualification. A unique source key includes the
node, VPS, event type, original integer-second timestamp and action. Duplicate
transport delivery cannot create another incident, mail chain or decision. Two
same-action events in the same second collide; distinguishing them requires a
future node protocol change. Existing incidents without this provenance never qualify for the initial rule.

An event received more than 24 hours after occurrence remains countable but
cannot initiate an automatic action. Future timestamps are audit-only until
their occurrence time becomes valid; they are never automatically replayed.
Unsent decisions expire after 24 hours. Resource contention retries the same
persisted decision while its trigger remains applicable.

Successful ownership transfer starts a shared accounting epoch and clears
warning state for all types. The original incident audit and last completed stop cooldown remain.
The transfer marker is reconciled against the complete chain and successful
Chown transaction finish, because node confirmations bypass model callbacks.
Rollback preserves the prior epoch. An uncertain transfer blocks dispatch.
Prior-owner decisions become ineligible; member incident history remains scoped
to the original incident owner and the current ownership epoch for registered
qualified reports. Ordinary unqualified manual history keeps its existing scope. Reboots, migrations and manual starts do not
reset accounting.

## Stop and mail recovery

A VPS row lock serializes ingestion, decisions and preparation. Physical stops
use the normal VPS resource lock and `TransactionChains::Vps::Stop`, with
`rollback_stop: false`. The completed stop transaction's `finished_at`, after
successful chain completion, starts the cooldown. Failed and uncertain stops
retain their action and chain identities and block further automatic stops.
Operators must inspect the transaction output and physical VPS state before
retrying or resolving that chain. The scheduler never automatically repeats an
uncertain physical stop.

Stop mail is prepared only after confirmed success. Mail progress is independent
of stopping, so a mail failure cannot restart or stop the VPS again. Retries use
the same message identity and inspect the mail transaction result; a completed
mail chain alone does not prove success because mail transactions use
`keep_going`. SMTP delivery retains its ordinary possibility of duplicates.
Counts in threshold mail describe the original decision; limits and future-stop
consequences use settings current when that mail is rendered or retried.

The existing incident-report task reconciles transfers, actions, pending
individual incident mail and threshold mail. Individual incident reports remain
in addition to threshold notifications. Disabling ordinary incident mail records
a prepared-or-intentionally-suppressed notification decision without inventing
a chain ID. Its nullable `notification_processed_at` timestamp is an acknowledgment,
not SMTP delivery proof. Ordinary mail
preparation failures roll back only that notification, leave it pending for
retry, and do not prevent automatic stop preparation.


## Registered sources and templates

Source adapters deliberately call `IncidentEscalation.ingest!` with a registered
key and accepted report attributes. The node adapter supplies trusted `oomd`
provenance and unchanged daemon protocol. The shared boundary checks qualification
before decisions. Registration alone does not enroll admin API, nodectl or mail
reports; a future manually qualified type needs its own explicit source adapter.
The scheduler discovers registered qualifying reports and outstanding actions,
reconciles and dispatches existing decisions, and never replays historical reports
to create new decisions. No arbitrary rule definitions or automatic codename
registration are supported.

The specific pair is `vps_memory_pressure_warning` / `vps_memory_pressure_stopped`.
The generic pair is `vps_incident_warning` / `vps_incident_stopped`. A registered
specific definition is used when installed; its absence selects the generic pair.
Disabled recipients, missing translations, rendering errors and SMTP failure do
not select another template. Intentional suppression finishes the mail decision
without advancing a queued-warning timestamp; a completed physical stop remains
completed. Template language fallback remains requested language then English;
the incident label follows the actual template language and recipient timezone.
Generic templates contain no memory-specific or site membership claims.

## Upgrade and rollback

Apply migration `20261030180000` before running the new backend or supervisor.
Install the four notification templates, deploy the backend in `observe` mode,
then update the WebUIs. Old node event messages remain supported; no coordinated
node update is required. Older clients ignore the additive summary fields.
Check counts and mail behavior before deliberately selecting `notify` or
`enforce`; enabling enforcement waits for a new qualifying incident.

For software rollback, select `observe` for all registered rules, reconcile dispatched chains and inspect
any uncertain effects before reverting backend services. Retain the additive
schema and audit history. Reverting software does not undo completed stops.
Schema rollback removes action history and overrides, so it is unsuitable for
recovery while feature actions or upgraded services remain active.
