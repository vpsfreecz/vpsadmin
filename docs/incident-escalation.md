# Incident escalation

An incident can match several configured policies. vpsAdmin saves one source
report and sends one ordinary email, regardless of how many policies match. The
producers validate their sources and deduplicate them; the engine handles ownership, policy counts,
locking, cooldowns and automatic shutdown. Process OOM reports remain separate.

## Policy declarations

The normal configuration loader reads `config/incident_escalation.rb` once per API,
supervisor and task process, before system settings are registered. A site supplies
it through the existing `configDirectory`; restart these processes after a change.
There is no hot reload or separate Nix rule catalog.

```ruby
IncidentEscalation.configure do
  rule :oomd do
    labels en: 'VPS memory-pressure incidents', cs: 'Incidenty přetížení paměti VPS'
    limits warning: 3, stop: 10
    templates warning: :vps_memory_pressure_warning,
              stopped: :vps_memory_pressure_stopped
    applies_if do |ctx|
      ctx.report[:codename] == 'oomd' && ctx.source[:kind] == 'node_vps_event' &&
        !ctx.source[:key].nil? && !ctx.source[:node_id].nil? &&
        ctx.source[:node_id] == ctx.vps[:node_id] && %w[restart stop].include?(ctx.source[:action])
    end
  end
end
```

Every declaration has a stable key, localized labels and positive signed
32-bit warning/stop limits. The stop limit must be at least the warning limit.
Optional `descriptions` provide localized plain text; optional `suppress_actions`
is a boolean, false by default. Templates default to the generic warning/stopped
pair. Keys match `[a-zA-Z0-9_]{1,59}`, preserving their spelling; duplicates,
including case variants that collide in the database, fail startup. Malformed templates and invalid declarations also fail startup.

When an ordinary `IncidentReport` is first saved, the creation callback evaluates
the configured policies. This includes manual/API reports, imported abuse notices
and node reports. Later saves do not repeat evaluation. A new policy for these
reports needs a declaration and a process restart. The example selector matches
whole-VPS memory-pressure events received through the authenticated node channel;
a manual report named `oomd` does not acquire that provenance.
With no site file or no declarations, the registry is empty. There is no implicit
OOM policy. Saved history and settings survive declaration removal.

For example, two ordinary non-OOM policies can independently select one report:

```ruby
IncidentEscalation.configure do
  rule :abuse_category do
    labels en: 'Abuse reports'
    limits warning: 3, stop: 8
    applies_if { |ctx| ctx.report[:codename] == 'abuse' }
  end
  rule :imported_abuse do
    labels en: 'Imported abuse reports'
    limits warning: 2, stop: 5
    applies_if { |ctx| ctx.report[:codename] == 'abuse' && !ctx.report[:mailbox_id].nil? }
  end
end
```

An optional `applies_if { |ctx| ... }` decides membership only when an ordinary
report is created. It must return exactly true or false. Site code is trusted:
keep selectors short and free of I/O, database queries and external effects.
There is no sandbox or scheduled callback execution. The deeply frozen context
contains captured values, without model objects:

- `now`: captured UTC evaluation time;
- `report`: id, codename, subject, text, detected_at, created_at, user_id, vps_id,
  filed_by_id, mailbox_id, ip_address_assignment_id, cpu_limit and vps_action;
- `source`: kind, key, node_id and action assigned by the trusted producer;
- VPS ID/node ID/state and owner ID/role/state;
- accounting epoch, policy key and prior matched 7/30-day counts;
- last queued warning and confirmed stop times;
- global mode, global/VPS overrides and shared stop exemption.

Selector counts exclude the incoming report. A true result records membership;
decision counts then include the report when its timestamp is within the window.
Absent selectors match. False results do not count. Exceptions or nonboolean
results are isolated selection errors. A matched report still counts if its
subsequent effective configuration is invalid. One failing policy does not prevent
other policies from matching or acting.

All configured policies are visited in lexical key order under the
existing settings/VPS serialization in the model creation callback. All outcomes
are saved before effects are prepared. Report insertion, every outcome and action
preparation share the save transaction. Unsaved parser dry runs do not match rules.
Updates and later processing never enroll rows. Database errors roll back creation
and propagate; selector errors are isolated to their rule. Selectors run once
per successfully persisted creation; transaction rollback can cause a later
attempt, so arbitrary selector side effects are unsupported.

## Saved membership and current limits

`IncidentPolicyEvaluation` stores one immutable outcome per report/key: nullable
`matched`, state `recorded`, `skipped`, `error` or `audit_only`, evaluation time and
one bounded JSON snapshot. The snapshot retains policy labels/descriptions,
policy/template identities, config-file digest, bounded captured context, limits, mode,
suppression and the decision `none`, `warning` or `stop`. Errors contain only a
safe stage/class, never exception messages. Report text is available to the selector
but is not copied into its snapshot. Action and mail state are separate.

Counts use indexed saved `matched=true` membership, source report event time and
the current original-owner epoch. They do not scan JSON or enroll by codename.
Windows use UTC durations with open lower and closed upper boundaries: seven days
for warnings, thirty for stops. Contributors and latest-incident times use the
same membership. New keys start at zero. Adding, editing, removing or renaming a
policy never reclassifies old reports; renaming creates a new identity.

Each policy's `incident_policy_<key>` SystemConfig category has mode and nullable
warning/stop overrides. Modes are `observe`, `notify` and `enforce`; observe is the
default. Effective limits use VPS override, then global override, then declaration.
Null inherits; omission preserves an existing value. The global mode is the action
ceiling. Declared suppression prevents actions while collection continues.
Shared `incident_enforcement_enabled=false` prevents escalation stops across all
policies while collection and eligible warnings remain active.

Current limits are declared facts even with selectors or zero matches. Reads
never invoke selectors. Invalid persisted effective combinations fail closed for
that policy: `configuration_valid=false`, null effective limits/status/mode/stop
permission, and no automatic action. Historical evaluation values never supply
current limits. Current threshold status does not predict a future action.

## API and frontends

Authenticated `IncidentPolicy` Index/Show at `/incident_policies[/{key}]` discovers
all active declarations, including those without overrides or matches. Keys are
opaque strings, not generated enums. Rows expose localized labels, descriptions and warning/stop periods. There is no
source-type admission catalog. Administrators also see `settings_category`.

`VPS::IncidentPolicy` Index/Show at
`/vpses/{vps_id}/incident_policies[/{key}]` returns every active declaration with
current counts, configuration validity, effective limits/status, global/effective
modes, stop permission, last incident/queued-warning times and latest saved
matched/error evaluation reference/time/state. A skipped match does not imply
current inapplicability. Administrators also see the raw nullable overrides.
Admin-only Update targets the key and changes only the two limit overrides.
The update is validated and audited atomically, then returns the authoritative row
synchronously.

VPS Index/Show expose shared permission, accounting epoch, confirmed-stop/cooldown
and outstanding physical-action state once. Batched `incident_warning_count` and
`incident_stop_threshold_count` count active policies at reached thresholds, with
stop precedence and invalid configurations excluded. The optional status filter
requires an explicit active policy key and runs before pagination.
Shared permission changes use a separate admin VPS Update without a policy key;
mixing them with other VPS changes is rejected before effects. This Update returns
an acknowledgement, so clients use a separate VPS Show to verify the stored
permission.

`IncidentReport::PolicyEvaluation` Index at
`/incident_reports/{incident_report_id}/policy_evaluations` projects compact saved
policy metadata, nullable `matched`, fixed warning/stop period days, counts, limits,
mode, permission, decision and state through the
authorized parent report. Members see matched successful/audit-only outcomes;
administrators can also read skipped/error states and safe diagnostics. It exposes
no callback, raw context or exception message. Saved retired keys remain readable.
IncidentReport Index accepts a separate `policy_key` filter: source rows qualify
through saved membership and notices through their owning action. Multiple matches
never duplicate source rows or pagination totals.

Both frontends display the typed policy collection. PHP provides an Incident
reports link to the existing filtered list and a separate Incident policies entry at
`?page=adminvps&action=incidents&veid=ID`. React has separate reports and policies
tabs. Policy pages show limits and counts for each configured policy. The overview
and VPS list show only reached warning/stop-threshold alerts. Each policy
has its own limit form; shared stop permission has one separate form. In PHP,
a blank limit inherits and a positive number is an explicit override, including
when it equals the default. Save writes the draft. API capability checks must cover these
resources and fields before enabling the feature. Members cannot change settings.

## Source, ownership and time boundaries

The initial site selector requires `node_vps_event` provenance, source key/node,
`restart`/`stop` action and `oomd` codename. Ingestion validates the current node.
Saved source-node attribution survives later VPS migration. The unique key includes
node, VPS, type, original integer-second timestamp and action. Same-action events
in one second collide; finer identity needs a node protocol change. Duplicates
preserve report text, evaluations, source log and mail identities, and do not try
newly configured policies.

Ordinary late/future creations receive their one matching attempt. Events more
than 24 hours late may count but cannot act; future membership counts only after
its event time enters a window, without action replay. Reports outside the current ownership epoch, including reports from a prior
owner, are audit-only and do not invoke selectors. Manual/API, imported
and nodectl reports visit all configured selectors. Generated notices bypass matching.
Undispatched decisions expire after 24 hours. Reads, retries, scheduled processing
and config changes never execute selectors.

Successful ownership transfer starts a shared accounting epoch and clears queued
warning cooldowns. Complete chain success plus successful Chown finish establishes
the epoch; node confirmations bypass model callbacks. An outstanding transfer
blocks dispatch; rollback preserves the earlier epoch. Confirmed stop cooldown
remains shared. Members retain existing original-report owner scope, with current
ownership epoch protection for trusted sources, evaluations, contributors and
notices, including transfer away and back. Notice scope uses its action epoch
even when physical completion occurs later. Unevaluated manual history keeps its existing scope.

API and node RPC creation prepare their ordinary source mail and explicit actions
in the same transaction as the report. Imported Handler/Send, node notification
recovery and legacy Process retain their existing notification ownership; matching
itself prepares no ordinary email. An explicit report Stop or Suspend saves policy
membership/counts/effective facts with decision `none`, leaving that requested
effect to the normal report chain. It does not imply a completed policy stop.

`nodectl incident-report` sends the allowlisted `create_incident_report` node RPC
write. The server checks the bound node's VPS, assigns current ownership and
`node_incident_report` provenance, validates administrator attribution and preserves
the report content, CPU limit and explicit action. The caller supplies one token
and timestamp per report before transport. The unique source key derives from
node and token; redelivery with identical facts returns the same report ID, while
conflicting facts fail. After a reply timeout, retain the printed token and exact
facts for reconciliation. Do not issue a fresh token or fall back to SQL for the
same uncertain report. Old raw-SQL rows retain ordinary processing but never gain
new memberships from scheduled work.

Notices expose nullable `notice_policy_key` and `notice_policy_label` from their
saved originating action after linkage/epoch checks. Ordinary reports return null.
Resource authorization still controls historical access; valid old-owner notices
remain available to authorized administrators without querying hidden triggers.

## One physical stop, per-policy outcomes

A policy chooses stop before warning when both qualify. Warnings have independent
seven-day cooldown and mail identity. A same-event eligible stop group suppresses
redundant warning candidates. A new stop requires a fresh qualifying source event
at least 24 hours after the last confirmed stop; no timer schedules another stop.
No earlier warning or grace period is promised. Manual starts remain available.

Stop candidates use existing `VpsIncidentAction` rows with their policy/evaluation
and nullable `stop_owner_action_id` follower link. Under VPS/resource locks, current
restrictions, digest, counts and expiry are revalidated for each candidate without
selectors. The remaining lexical key/ID owner submits one normal
`TransactionChains::Vps::Stop` with `rollback_stop: false`; every eligible follower
is atomically bound to that chain. A revoked or failed candidate cannot block an
otherwise eligible policy. Resource contention defers the unsubmitted group.

Outstanding physical work excludes another chain for the VPS. Failed/uncertain
outcomes keep that exclusion; a follower never replays the operation. Complete
chain success and successful Stop finish confirm every submitted action and set
the shared cooldown once. Each policy may then create one policy-named stop notice
and its own delivery. Skipped/revoked policies do not claim the stop. Mail failure
or retry never retries the physical stop. Already dispatched work may finish after
settings/configuration changes or removal; saved metadata supports reconciliation.

## Source mail, notices and contributors

Ordinary node reports store localized source facts. Rendering and owner selection
share ingestion serialization; unsupported languages fall back to English and the
ambient locale is restored. Source logging and ordinary delivery happen once,
independently of policy count. Ordinary notification preferences remain effective.

The `vps_incident_report` template receives `incident_policies`: a lexical-key
ordered array of saved matched summaries with complete facts in recorded or
audit-only states. Each contains a key and label in the actual rendered language,
evaluation time, 7/30-day counts, limits,
mode/exemption/suppression, periods and `stop_enforced`. Skipped, error and incomplete
outcomes are omitted; an empty array renders source facts only. No first-policy
shortcut, count aggregation or current-setting lookup belongs to this projection.

Each policy table shows Period, Incidents, Limit and Action for its warning and
stop windows. Counts and limits are anchored at evaluated_at, without recomputing
a past calendar window from the incident timestamp. Multiple summaries identify
their policy; the conditional possible-stop sentence appears once when any saved
summary permits it.

Aggregate warning and shutdown messages retain the action's saved counts, metadata
and contributors. While the policy remains registered, they apply current global
and VPS limit overrides, global mode and shared shutdown permission to the action's
saved policy base. A later declaration change affects live summaries and new
evaluations, but does not replace that saved base. For example, changing a declared
shutdown limit from 10 to 20 leaves delayed mail at its saved base of 10; a current
override of 25 makes the mail show 25. The live summary without an override shows
20. These mail limits do not represent the live policy configuration. If the
policy has been removed, the notice retains saved effective limits, uses observation
mode with actions suppressed, and omits possible-stop guidance.

Rendering and retries never rerun selectors. Stored report text and rendered
MailLog bodies remain unchanged through duplicates or later language/configuration
changes.

Warning decisions and confirmed stops create separate `IncidentReport` notices
with `source_kind=incident_policy_notice`, no executable CPU/VPS action and unique
per-action notice/message identities. Their saved localized policy labels identify
the explanation. All ordinary processing/count entry points exclude notices.
Index/Show expose nullable `notice_kind` (`warning`, `stop_completed`), raw integer
`trigger_incident_report_id` and `notice_mail_state` (`pending`, `queued`, `sent`,
`failed`, `uncertain`, `suppressed`). Ordinary reports return null. Missing/unsafe
trigger references are omitted. Pending means not queued; queued proves no SMTP
success, and sent proves SMTP success without inbox delivery. No private action
error, recipient or MailLog endpoint is exposed.

Actions freeze at most five matching contributors in the actual decision window,
including an eligible trigger. Selection uses newest event time/ID first, retaining
that display order. Saved IDs, safe plain subjects (160 characters), event times,
total/window and decision time do not change on retry. Missing/inaccessible reports
retain their slots without description/time/link and are never replaced. Templates
show only available entries against the saved total; empty details are omitted.
A transferred owner receives no predecessor evidence.

Existing contributor variables retain their meaning: `contributing_incidents`
contains ID/time/subject/URL/availability; count/shown/omitted/window, decision time
and snapshot availability explain the bounded set. Times are native Time values
rendered in the recipient timezone. Authenticated detail links use configured
`webui.base_url`; current history uses `policy_key`, distinct from the frozen set.
Invalid/empty bases produce no link. Escape all text and URLs in their context.

The saved action snapshot includes effective decision facts and policy metadata,
so a deleted trigger or retired declaration does not erase confirmed outcomes.
Specific warning/stopped template names come from that saved metadata, falling
back to the existing generic pair when the specific definition is absent. Disabled
preferences, rendering errors and send failures never choose another identity.
Language fallback is requested language then English, with the saved policy label
localized to the actual rendered language. Stop mail describes confirmed past
stops and retains manual restart guidance; it does not claim current running state.

Reconcile ordinary and aggregate templates before switching producers. Managed
installations use normal template reconciliation; `install_defaults!` only creates
missing definitions. Existing overrides must be updated explicitly. Old rendered
messages are unaffected. An old ordinary template without the collection payload
is not a complete supported rollout.

## Recovery and schema boundary

Before undispatched effects, current restrictions may suppress but never loosen
the saved decision. Exact site-file bytes, including comments, define the digest.
Changed/removed declarations cannot dispatch old decisions; queued physical work
retains its identity and reconciles from the chain. Operators must establish failed
or uncertain physical outcomes before ordinary reconciliation. SMTP retains its
normal duplicate-delivery possibility.

The incident task processes transfers, actions and pending ordinary mail without
selectors. Disabled ordinary mail acknowledges `notification_processed_at` without
inventing a chain. Preparation failure leaves only that notification pending and
does not roll back or retry a physical stop.

Deploy compatible backend code and site declarations together, and restart the
API, supervisor and task processes before activating the policies. Install the
`create_incident_report` RPC handler before upgrading nodectl. Do not use a nodectl
version that writes incidents directly with SQL after activation: those reports
bypass creation-time matching and are never evaluated later.

Migration `20261030180000` introduces policy evaluations, settings, actions and
links between actions that share a physical shutdown. Apply it to its immediate
predecessor schema before starting compatible API, supervisor and task processes.
Downgrading the schema removes incident policy history and is unsafe while services
or actions depend on it. Keep
schema/data when rolling software back to a compatible version and reconcile
submitted work; completed stops are not undone. Deploy compatible typed clients
and capability-gated frontends before enabling new calls. Source publication,
client publication, activation and default-branch integration are separate steps.

## Administrator overview and evaluation history

`IncidentPolicyExposure.Index` (`GET /incident_policy_exposures`) lists active
VPS/policy pairs with saved matches in the last 30 days. It includes physically
stopped VPSes and inactive owners. A selector is never run by a read. Counts include reports
from the current owner within the accounting period established by the latest
successful ownership transfer, including transfers awaiting reconciliation. Generated notices do not count.

The exposure API uses ordinary VPS, User and Node references. Its internal and
mail projections retain flat IDs and presentation fields. Filters are `vps`,
`user`, `node`, active `policy_key`, threshold `status` (including `invalid`),
`effective_mode` and `stop_enforced`. The default includes all current matches.
Ordering runs across VPS/policy pairs on the server before paging. `sort` accepts
`severity`, `vps_id`, `user_login`, `policy_key`, `count_7d`, `count_30d`,
`warning_remaining`, `stop_remaining` and `last_incident_at`; `direction` reverses
only the primary key. Nulls sort last. Ties use the remaining
count, latest incident time, VPS ID and binary policy key, in that order. Severity orders failed/uncertain
shared stops, invalid configuration, pending shared stops, stop thresholds,
warning thresholds, near limits and rows below the limits. Invalid limits stay null.

`IncidentPolicyEvaluation.Index` (`GET /incident_policy_evaluations`) returns
one row per saved evaluation, with at most one attached action. Original VPS/owner IDs and
retired policy keys remain visible when their current names no longer exist.
Saved counts, limits and decisions are never recomputed from current settings.
Missing old facts remain null. Raw snapshots, selectors, private errors, mail
bodies and recipients are excluded. Both actions, including their capability
metadata, require the administrator role; support and member roles are denied.

Both actions use offset paging: `offset` defaults to 0, `limit` to 25 (maximum
100). Global metadata always includes `total_count`, `offset`, `limit`, nullable
`next_offset`, `as_of` and `read_at`, including on an empty page. The optional
`as_of` is normalized to whole UTC seconds and must be within the past 24 hours.
Reuse the returned cutoff across pages; Refresh selects a new cutoff. It fixes
count windows and excludes later evaluations, but does not freeze settings,
ownership or current action outcomes across requests. Each collection selects
its total, sorted page and mutable facts in one SQL statement. No read locks,
selectors, reconciliation or writes are performed.

History scopes are `violations` (default: a saved threshold or an action),
`matched`, `all` and `outstanding`. Other filters are `policy_key`, original
`vps_id`/`user_id`, saved `decision`, current `action_kind`, `action_state` and
`mail_state`. Ordinary history uses `from <= evaluated_at < to`. The default period is
the 30 days before the cutoff; the maximum span is 366 days. The outstanding scope ignores
both dates and returns them as null: it includes unresolved non-suppressed work
of any age. History orders by evaluation time then ID, in the same requested
direction. Its global metadata also declares the effective `from` and `to`.

Current action and mail outcomes can postdate the selected evaluation period.
A confirmed shutdown requires a successful native Stop transaction.
Completion of a warning action does not establish a shutdown. Rows sharing `physical_stop_action_id`
describe one physical stop. Queue time comes from the retained current MailLog;
finish time comes from its Send transaction. Mail `sent` means SMTP
acceptance, not inbox delivery. A completed stop can still have failed mail.

### Daily policy summary

The optional registered `incident_policy_summary` hash adds three bounded
collections to the existing daily report: all current matches, recorded activity
in the rolling 24-hour period, and currently outstanding work of any age. They
use the same whole-second UTC cutoff and shared read projection as the API.
Each collection is internally consistent; the three collections do not form one
immutable database snapshot. Each collection
carries `total_count`, `rows`, `omitted_count` and a nullable prepared URL, with
at most 25 rows after server ordering. Row times are native UTC `Time` values.
Existing report sections, recipients and scheduling remain unchanged.

Activity has one row per evaluation and includes a qualifying evaluation,
confirmed shutdown, mail queue or finish time, or update to a failed or
uncertain outcome during the period. Its `activity_at` is the latest qualifying time; ties prefer
stop completion, mail finish, mail queue, evaluation, then action update. Old
evaluations can appear when their stop or mail finishes in the period. The stored outcome and latest mail reference can change on retry, so these
records do not capture every state change or retry. `action_updated` records
the latest update, not the time of the first failure.

Older producers can omit the hash; templates then omit these sections. Present
empty collections say that no matches, activity or outstanding actions were
found. Truncated collections state how many rows are shown, the total and how many
were omitted. Links are
prepared by the producer, nullable when the WebUI base URL is invalid, and may
show later current state. Templates only format supplied facts. Rollback may
remove these reads or sections without changing persisted evaluations/actions
or existing API and report routes. Deploy the API before enabling new client
calls, or retain capability guards; generated clients alone do not establish
server support.
