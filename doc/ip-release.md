# IP release campaigns

Administrators create campaigns from owned, unassigned public IP allocations.
The default preview selects IPv4; IPv6 allocations are also supported. Creating a
campaign snapshots its addresses and owners. Each campaign can contain at most
100 allocations. Preview and request lists are paginated; a WebUI selection
contains addresses from the displayed page. Create further campaigns for more
addresses. This limit bounds synchronous notice and release work. An address can belong to only one
open campaign until it is released or the campaign is closed.

The planned release date defaults to seven days. It is advisory: only an explicit
administrator action releases addresses, and that action is available at any
time, including before notices have been sent. There is no scheduled release.

## Actions

`IpReleaseCampaign.Candidates` previews the selection. `Create` takes the selected
IP IDs, a label, an optional deadline and `allow_keep` (default true). Campaign
membership is fixed after creation. `Update` changes the label, deadline or
retention policy. Edits do not send email.

`Notify` queues initial notices with `event=requested`, skipping requests already
notified. `event=reminder` queues another notice for previously notified users. Both use the normal
mail queue. Both include only addresses still eligible under the current policy;
no message is queued when none remain. Reminders can be repeated and use the
current planned date and retention policy. Text and HTML variants include location
labels, and the HTML button opens the request without changing it. Delivery state has no effect on release eligibility. The notice link
opens the user's request in the WebUI after login. Each queued notice has an
append-only record with its event, mail log, administrator and timestamp. Users
can view the dates and subjects of their notices.

Users can view their own `IpReleaseRequest` records and use `Keep` to save a
nonblank reason (up to 2,000 characters) for selected request-address IDs. Reasons
can be submitted or changed until an administrator starts releasing the address or closes the
campaign, including after the deadline. Reasons protect addresses while
`allow_keep` is true. Setting it to false overrides their effect; setting it back
to true restores protection for unreleased addresses. Reasons remain recorded.

Administrators can independently set or remove per-address exemptions through
`IpReleaseRequest.Address.Exempt`. An exemption requires a reason and protects
its address regardless of `allow_keep`. A null reason removes the exemption.

`Release` processes the whole campaign using its current policy. It retains
assigned addresses, including addresses on stopped VPSes and export interfaces.
Addresses granted access to an NFS export are also retained, even without an
interface assignment. Administrator exemptions and effective user reasons protect
addresses independently. Missing users and users in deletion states, changed owners and changed or missing
allocations are permanently excluded from that campaign. Exclusion time and reason
are retained, and the address can enter a new campaign. Suspended users are still
eligible. Exclusion never changes the current owner's quota, ownership or DNS. Each address returns a release result;
addresses blocked by an IP or quota lock can be retried by invoking `Release`
again after the owning transaction finishes.

Ownership and quota changes use the existing IP update transaction chain.
DNS transfer grants, reverse DNS and user-created host addresses are cleaned up
through the existing transaction engine. While cleanup runs, the address remains
owned and charged, and its status is `releasing`. Ownership, quota and the final
release record change together only after cleanup succeeds. Addresses without
asynchronous cleanup are released immediately.

An initiated attempt cannot be changed by a reason, exemption, policy edit or
campaign closure. Those changes govern subsequent attempts. Repeated Release
calls skip attempts still running. Failed or rolled-back cleanup keeps ownership
and quota; inspect the linked chain, resolve any fatal state, then invoke Release
again. No retry is scheduled. A pending cleanup holds the original user's lifecycle resource lock and quota lock, so
other addresses charged to the same quota may need a later manual attempt.

The campaign item and its linked chain are the authoritative release audit:
original owner/allocation, initiating administrator and session, attempt time,
confirmed release and cleanup outcome. The release timestamp identifies the
administrator's attempt; the transaction log records completion timing. Final
database confirmations bypass PaperTrail callbacks, as in existing deferred IP
assignment workflows; the pending attempt remains in PaperTrail history.

`Close` ends notices, edits, exemptions, retention submissions and releases. It
frees outstanding campaign claims and retains history. Closing a campaign does
not undo an IP release or cancel an already initiated attempt.

## Deployment and rollback

Apply the additive database migration before deploying the API and WebUI. Deploy
the API changes to all writers before using campaigns: the assignment paths must
use the updated IP locking and quota accounting. Host-address creation and
assignment, PTR changes, DNS transfers and NFS export grants must share the parent
IP lock. Wait for IP, host/DNS/export and quota transaction chains started by older API versions
to finish before using campaigns; those chains lack the new locks. No new node
transaction type or vpsAdminOS update is required.

Before starting any API rollout, pause administrator changes to network role and
IP version and new IP registration through Network.Create, Network.AddAddresses
and IpAddress.Create. Keep these writes paused until every API writer is upgraded
and registrations started by older writers have finished. Older writers do not enforce the new
network invariant or take its registration lock. Keep the same administrative
restriction during rollback. After all writers have been reverted and old work
has drained, registrations may resume only while role/IP-version changes remain
paused; populated-network conversions still require accounting reconciliation. This
restriction applies to ordinary network and IP operations as well as campaigns.

Before release or ownership transfers, audit populated networks' role and IP
family against their allocation and accounting history, including addresses with
a recorded charge environment. Older APIs allowed these fields to change on
populated networks. A non-null charge environment therefore does not prove that
the allocation was charged to the resource implied by its current network.
Verify the network address family and the affected owners' environment usage for
public IPv4, private IPv4 and IPv6. Use reliable operation or maintenance records
to establish prior changes. If the history is ambiguous or the accounting does
not agree, reconcile the affected allocations and quota before releasing or
transferring them. The migration does not infer or repair historical resource
types.

Before enabling campaigns, audit owned addresses with missing charge identity:

```sql
SELECT ip.id, ip.ip_addr, ip.prefix, ip.user_id, ip.network_id,
       GROUP_CONCAT(DISTINCT l.environment_id ORDER BY l.environment_id) AS available_environments
FROM ip_addresses ip
LEFT JOIN location_networks ln ON ln.network_id = ip.network_id
LEFT JOIN locations l ON l.id = ln.location_id
WHERE ip.user_id IS NOT NULL AND ip.charged_environment_id IS NULL
GROUP BY ip.id, ip.ip_addr, ip.prefix, ip.user_id, ip.network_id;
```

Older registration paths and the original charge-environment migration left
some free owned addresses without this identity. New registrations and managed
network additions record it. Managed-network additions require the owner and
charge environment together. Owned addresses with missing provenance cannot be
assigned or released until it is reconciled. Existing rows are not guessed or backfilled: the
current network locations do not prove where an old allocation was charged.
For each legacy row, reconcile the owner's environment quota usage against
allocation history, then explicitly set `charged_environment_id` to the verified
environment using an audited administrator maintenance session. Preserve quota
usage when correcting only this missing identity; reconcile any actual accounting
discrepancy separately. Campaign release reports these rows as failed and leaves
ownership/quota intact until reconciliation. Other campaign addresses can proceed.

Network role and IP version cannot be changed while a network contains IP
allocations. Converting a populated network requires a separate audited maintenance
operation that also reconciles quota; ordinary Network.Update does not perform it.

The 100-allocation cap and seven-day suggested deadline are fixed contracts shared
by the API and WebUI. Changes must update their UI limits, copy, localized errors
and documentation together. The capacity contract test verifies that a complete
campaign fits the member's address fetch.

The built-in English templates are `ip_release_requested` and
`ip_release_reminder`. Deploy the matching vpsFree.cz notification overlay after
the API knows these events. Resource and node message formats stay compatible.
Disowning through the existing `IpAddress.Update` action now retains ownership
until asynchronous cleanup succeeds; callers must use its existing transaction
state metadata before assuming completion. Disowning without asynchronous cleanup
remains immediate. The WebUI's combined disown-and-remove action waits for the
disown result before removing the route. If cleanup is still pending or fails,
the route remains and the page links to its transaction. Submit removal again
after resolving or completing that transaction. Using the new resources requires
refreshed API discovery.

Before a code rollback, stop campaign operations and reconcile active transaction
chains. Keep the additive tables to preserve history. Remove the new notification
overlays before reverting to an API registry that does not recognize them.
Rolling back code or the migration cannot recover already redistributed IPs.
