# IP release campaigns

Administrators create campaigns from user-owned IP allocations which are not in
use. Public and private allocations are supported; the default preview selects
public IPv4. Assigned parent interfaces, host assignments, routing dependencies
and NFS export grants exclude an allocation from both preview and creation.
Locked allocations and users in deletion states are also excluded. An address
can belong to only one open campaign until it is released, excluded or the
campaign is closed.

Campaigns have numeric IDs, a planned date and a retention policy. There is no
custom label or campaign allocation limit. WebUI address lists show 500 rows per
page. Expected campaign size is hundreds of allocations; API actions enumerate
records in batches using the existing transaction and mail queues.

The planned release date defaults to seven days. It is advisory: only an explicit
administrator action releases addresses, and that action is available at any
time, including before notices have been sent. There is no scheduled release.

## Actions

`IpReleaseCampaign.Candidates` previews the selection. `Create` takes the selected
IP IDs, an optional deadline and `allow_keep` (default true). Campaign
membership is fixed after creation. `Update` changes the deadline or
retention policy. Edits do not send email.

`Notify` queues initial notices with `event=requested`, skipping requests already
notified. `event=reminder` queues another notice for previously notified users. Both use the normal
mail queue. Both include only addresses still eligible under the current policy;
no message is queued when none remain. Reminders can be repeated and use the
current planned date and retention policy. Text and HTML variants include location
labels, and the HTML button opens the request without changing it. Delivery state has no effect on release eligibility. The notice link
opens the user's request in the WebUI after login. Each queued notice has an
append-only record with its event, mail log, administrator and timestamp.
Notice history is available only to administrators, including the request-scoped
API endpoint. Subjects and message bodies use singular or plural forms based on
the allocations included in that message, even when a reminder contains fewer
addresses than the original notice.

Users can view all their own `IpReleaseRequest` records, including closed
requests. They can use `Keep` to save a nonblank reason (up to 2,000 characters)
for selected request-address IDs. Reasons
can be submitted or changed until an administrator starts releasing the address or closes the
campaign, including after the deadline. Reasons protect addresses while
`allow_keep` is true. Setting it to false overrides their effect; setting it back
to true restores protection for unreleased addresses. Reasons remain recorded.

Administrators can independently set or remove per-address exemptions through
`IpReleaseRequest.Address.Exempt`. An exemption requires a reason and protects
its address regardless of `allow_keep`. A null reason removes the exemption.
`IpReleaseCampaign.Exempt` applies the same operation to selected request-address
IDs across users in one campaign. Supply a nonblank `reason` to set exemptions,
or `remove: true` to clear them without a reason. Omitting both fails validation
and leaves existing exemptions intact. The explicit removal flag also works with
PHP clients that reject null values for required input parameters.
It validates the whole selection under the
campaign lock and ordered address-row locks; invalid or changed entries reject
the entire batch. The single-address action delegates to this operation.

`IpReleaseCampaign.Address.Index` lists the complete campaign selection, including
original owners and locations. `IpReleaseCampaign.Notice.Index` lists its notice
history across recipients. Both are administrator-only. Request-scoped lists and
email links continue to work.

Reasons and exemptions store the authenticated actor's numeric ID and time.
Administrators see those IDs and the current login when available. Raw IDs remain
available after account deletion; they deliberately do not require a resolvable
live User resource. Members see their reason and administrator exemption with
timestamps, without administrator identities. Their request API exposes only ID,
deadline, `can_keep` and `can_assign`. Address responses use an explicit member
whitelist: snapshot address, prefix, size, location, current protection, reasons
and timestamps, and a nullable `assign_ip_address_id`. This numeric assignment
link disappears when ownership/allocation changes; it cannot expand the new
owner's live IP resource. Campaign metadata, release-attempt results, exclusion
diagnostics, cleanup state and transaction references are administrator-only.
Updating an exemption replaces its
current reason and actor; normal PaperTrail history retains prior changes.

`Release` processes the whole campaign using its current policy. It retains
assigned addresses, including addresses on stopped VPSes and export interfaces.
Addresses granted access to an NFS export are also retained, even without an
interface assignment. Administrator exemptions and effective user reasons protect
addresses independently. Missing users and users in deletion states, changed owners and changed or missing
allocations are permanently excluded from that campaign. Exclusion time and reason
are retained, and the address can enter a new campaign. Suspended users are still
eligible. Exclusion never changes the current owner's quota, ownership or DNS.

Each `Release` creates one administrator-only `IpReleaseAttempt`, returned by the
action with its transaction state ID. `IpReleaseCampaign.Attempt.Index` and
`Show` expose the attempt history. Each attempt records its initiating admin ID,
time, selected address membership, shared chain and any preparation failure.
The membership remains available after retries and user deletion. IP counts are
allocation counts, so each IPv6 prefix counts once.

The complete eligible batch uses one transaction chain and shares user, IP and
quota reservations. A conflicting reservation aborts preparation of the whole
batch, including addresses without DNS cleanup. The error identifies the busy
resource and its chain when available. Missing charge provenance also aborts the
batch. No ownership or accounting changes are committed on preparation failure.
Changed or protected allocations are excluded from the batch after current
locked validation. An attempt with no eligible allocations records that outcome
without creating an empty transaction chain.

The shared `Ip::Disown` chain removes DNS transfer grants, reverse DNS and
user-created host addresses. It combines quota changes by original owner,
recorded charge environment and resource. Campaign releases always stage a final
NoOp confirmation, even without DNS cleanup. Every selected IP remains owned
and charged while the batch runs. Ownership, quota and release markers are
applied together in the transaction engine's final database transaction.
Ordinary single-IP `IpAddress.Update` still completes immediately when no
asynchronous cleanup is needed; ownership transfers retain their existing
behavior.

Policy edits and campaign closure do not cancel a prepared batch. Reasons and
exemptions cannot change addresses in that batch. Repeated release submissions
return the existing active attempt, including after closure. There are no
automatic retries. After a completed rollback, ownership and quota remain intact;
an administrator can retry, which rechecks current protection and ownership.
Fatal or missing chains require operator recovery. Marking a fatal chain resolved
alone is insufficient: finish its confirmations and release its reservations.
A resolved chain with partially applied release markers still needs attention.
Reconcile the complete batch before retrying. Manual transaction recovery can
apply individual confirmations, so operators must preserve the batch invariant.

The latest attempt and its linked chain provide the campaign-level outcome:
in progress, rolling back, released, rolled back, preparation failed, nothing
eligible, or operator attention required. Historical membership and per-address
snapshots preserve the original allocation/owner. Final database confirmations
bypass PaperTrail callbacks, as in existing deferred IP assignment workflows;
the pending item changes remain in PaperTrail history. The release timestamp
identifies the attempt start; transaction logs record completion timing.

IP assignment history records VPS use, not allocation ownership. Disowning an
unassigned address does not create or remove assignment entries. An address that
has never been assigned to a VPS therefore has no assignment history.

`Close` ends notices, edits, exemptions, retention submissions and releases. It
frees outstanding campaign claims and retains history. Closing a campaign does
not undo an IP release or cancel an already initiated attempt.

## WebUI

Open **Cluster → IP release campaigns**. Navigation and current campaign actions
have separate sidebar sections. **Send initial notices** appears when eligible
recipients remain without an initial notice. **Send reminders** appears only for
previously notified recipients with eligible addresses. Campaign `Show` exposes
`can_send_initial_notices`, `can_send_reminders` and `can_release`; availability
uses the same recipient/protection checks as the operations. Release can also
process changed allocations that need permanent exclusion. Dates and mail
delivery are never prerequisites for release. Closed campaigns expose history.

Creation provides multi-select IP versions, networks and locations, optional
user ID and public/private/both access. Values within one filter are combined
with OR; separate filters are combined with AND. `Candidates` accepts comma-separated `versions`
(default `4`), `networks` and `locations` (empty means unrestricted), `user`,
and `access` (`public_access`, `private_access`, or `all`; default public).
The filter lists use scalar query strings so they work with the pinned PHP
client, which does not serialize array-valued GET parameters.

The preview stores explicit matching IDs and display data in the authenticated
WebUI session. Select all matches or exclude individual rows across 500-row
pages. Selection and settings survive page changes; changing filters starts a
new preview. A preview is isolated from other tabs and accounts. The session
retains at most ten previews; this does not limit campaign size. Creation
revalidates the selected allocations atomically and does not add new matches.
Creating a campaign does not send email.

Campaign details show all addresses in one table, with their original owners,
current protection, user reasons, administrator exemptions and release results.
The latest release outcome and attempt history appear above the addresses.
Transaction-chain links include their numeric IDs and belong to the attempt,
so they are not repeated on every IP row. Release controls disappear while an
attempt is active or needs operator recovery.
Use the header checkbox to select all editable rows on the current page, or
select individual addresses, to set one exemption reason or
remove exemptions. User reasons are independent and remain recorded. Released,
releasing and excluded addresses cannot be selected.

**Notice history** lists initial notices and reminders queued for the campaign.
Members see only their own release date, addresses, protection/reasons and
applicable keep/assign controls. Their sidebar links to Networking and their
request list; it does not offer notice history or a link to the current request.
**Close without releasing IPs**
ends further campaign operations without starting a release. Remaining addresses
stay owned, already initiated releases continue, and history remains available.
A closed campaign cannot be reopened.

The campaign list, creation, address tables and Notice history use the usual
WebUI sidebar and table structure. Action forms and confirmation messages explain
the operation separately from the campaign data. The administrator campaign list
has separate Total, Release and Keep columns with numeric counts and explanatory
header tooltips.

Campaign Index and Show expose administrator-only `total_ip_count`,
`to_release_ip_count` and `kept_ip_count`. Each snapshot row counts once,
regardless of subnet size. Total includes all historical rows. To be released
counts eligible rows in an open campaign and any release in progress, even
following closure. Kept counts assignment/routing/export use, administrator
exemptions and user reasons honored under the current policy. Released and
changed rows, and unresolved rows after closure, count only toward Total; the
three counters are not a partition. Counts use the release protection evaluator
and are loaded once for each campaign response in bounded batches, including
campaigns expanded through request associations. Counts use no persisted
counters or new locks. They are a current summary, not a reservation;
Release rechecks every allocation before changing ownership.

## Ownership prerequisites and operations

Campaigns use the shared [IP ownership and accounting rules](ip-locking.md).
These also govern ordinary IP registration, assignment, disownership and account
teardown. The [ownership operations guide](ip-ownership-operations.md) covers
legacy charge audits, reconciliation and pending-chain recovery.

For an installation transitioning from older ownership writers, follow the
[ownership reservation upgrade guide](upgrade-ip-ownership-reservations.md)
before using campaigns. It covers schema and writer ordering, API discovery,
notification compatibility and software rollback restrictions.
