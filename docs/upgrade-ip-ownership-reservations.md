# Upgrade to coordinated IP ownership reservations

## Applicability

This guide covers the transition from the multi-location network schema with
`ip_addresses.charged_environment_id` and older ownership writers to the
coordinated ownership/accounting writers and IP release campaigns introduced
with migration `20260909170000_add_ip_release_campaigns`. The charge-environment
column predates this migration; adding campaign tables does not repair legacy
accounting or prove that all writers follow the reservation protocol.

The target API includes the [ownership invariants](ip-locking.md), shared batch
disownership and [campaign behavior](ip-release.md). This transition affects
ordinary IP and network operations even if campaigns will not be used. The
additive campaign schema uses the existing resource-lock format and node
protocol; it requires no new node transaction type or vpsAdminOS update.

## Before upgrading

1. Pause administrator changes to network role and IP version and new IP
   registration through `Network.Create`, `Network.AddAddresses` and
   `IpAddress.Create` before starting any API rollout. Keep them paused until
   every API writer is upgraded and registrations started by older writers have
   finished. Older writers neither enforce the populated-network invariant nor
   take its registration lock.
2. Audit historical network semantics and charge provenance using the
   [ownership operations guide](ip-ownership-operations.md#accounting-audit-and-reconciliation).
   Include allocations that already have a charge environment. Reconcile
   uncertain resource types before release or ownership transfers and missing
   charge identities before enabling campaigns. Never backfill from current
   network locations alone.

## Deployment order

1. Apply the additive campaign migration before deploying the API and WebUI.
   Retain accounting evidence needed for legacy reconciliation.
2. Deploy compatible API and supervisor writers everywhere before using
   campaigns. Assignment and quota paths must follow the shared protocol;
   host-address creation/assignment, PTR changes, DNS transfers and NFS export
   grants must participate in the parent IP reservation.
3. Finish IP, host/DNS/export and quota transaction chains started by older API
   versions before enabling campaigns. Their pending work lacks the new
   reservations even after the processes have been upgraded.
4. Deploy the matching WebUI after the API and refresh API discovery. Its
   campaign counts, input filters and member output depend on that API contract.
   The Networking and DNS views also need the API's additive `usable_for`
   filter; older clients can continue using exact `purpose` filtering.
5. Install notification overlays only after the API registry recognizes
   `ip_release_requested` and `ip_release_reminder`. The API supplies built-in
   English templates for these events. Use overlays compatible with their
   current variables and text/HTML variants.
6. Resume registration and network edits after all writers are compatible and
   older registrations have drained. Populated-network role/IP-family changes
   remain prohibited through ordinary API updates. Enable campaigns only after
   the audit and older-chain prerequisites above are satisfied.

Verify API discovery and member/admin campaign responses before exposing the
WebUI. Callers of ordinary `IpAddress.Update` must continue following its
transaction-state metadata: asynchronous disownership retains ownership and
quota until cleanup succeeds. See [disownership](ip-locking.md#disownership)
for completion behavior and [pending-chain recovery](ip-ownership-operations.md#pending-chains)
for unresolved work.

## Software rollback

Stop campaign operations and reconcile active transaction chains before
reverting code. Fatal or incomplete release attempts need operator recovery;
removing reservations or reverting software does not complete their database
confirmations. Preserve the batch guarantees described in the operations guide.

Keep the additive campaign tables and history. Remove overlays using the new
notification events before reverting to an API registry that does not recognize
them. Revert the WebUI before the API and refresh discovery so the UI does not
request unsupported actions, fields or filters.

Keep network role/IP-version edits and new registration paused throughout
rollback. Once all writers are reverted and older work has drained,
registrations may resume only while role/IP-version changes remain paused.
Populated-network conversions still require accounting reconciliation; older
software does not enforce the new invariant.

Rolling back code or the migration cannot recover addresses already released
and redistributed. Preserve ownership/accounting history and establish current
ownership before any recovery operation.
