# IP ownership, accounting and locking

## Reservations

IP writers use vpsAdmin resource reservations and SQL row locks for different
parts of an operation. The resource reservation excludes another writer until
the transaction chain finishes, including rollback. SQL locks give the API a
current read while it prepares that chain; they end with the database
transaction and do not remain held while a node executes commands.

The generic `Lockable` and `TransactionChain#lock` interfaces are unchanged.
The domain helpers are:

- `IpAddress#lock_current!(chain, actor: nil)` reserves the IP and reloads it.
  Supplying an actor also rechecks ownership. An already-held reservation does
  not suppress the reload at a public entry point.
- `IpAddress.lock_all_current!(chain, ips)` reserves a known set in ID order
  before reloading it. `HostIpAddress.lock_all_with_ips!` reserves all parents
  before their host records; `HostIpAddress#lock_with_ip!` handles one host.
- `IpAddress#with_current_lock` wraps a synchronous writer in a database
  transaction and a temporary resource reservation. Host creation uses it.
- `IpAddress#require_reservation!` verifies an included chain's explicit use of
  pending in-memory state. The `reserved_ips` option on export-grant chains is
  for assignments already reserved by the containing route/allocation chain.

An IP can have no explicit owner while belonging to a VPS. Its effective owner
then changes when the VPS changes owner, even if the IP row stays unchanged.
Authorization and export-grant validation refresh that relationship using SQL
shared reads. Interface ownership checks also use shared reads so concurrent
readers do not take conflicting exclusive locks merely to check ownership.

Automatic VPS and export allocation and migration replacement share the same
selection criteria before and after reservation. The second check uses current
reads, including owner, assignment, location, purpose and selection policy.
Public allocation actions report a changed selection so the caller can retry.
Internal route removal also reserves and revalidates addresses before computing
quota changes.

Automatic VPS allocation and migration replacement reuse owned addresses only
when ownership is enabled at the destination and the address is already charged
there. Other owned addresses remain available for explicit assignment, which
transfers their quota through `NetworkInterface::AddRoute`. Export selection does
not use this restriction because it does not change an address's charge.

These helpers depend on every ownership/assignment writer participating in the
IP reservation protocol, including host-address, PTR, DNS-transfer and export-grant
writers. The [upgrade guide](upgrade-ip-ownership-reservations.md) describes how
to transition older writers and in-flight chains. The reservation protocol uses
the existing node protocol and stored resource-lock format.

## Accounting

IP accounting uses `adjust_resource!(resource, delta:, ...)`. It shares
validation and allocation with the absolute setter; `reallocate_resource!`
still takes an absolute value. Relative changes lock current owner, allowance
and usage rows, and reserve the existing user resource for the chain lifetime.
Transfers lock all affected accounting owners in ID order first. Synchronous
changes release the reservation when their database transaction finishes.

Deferred adjustments describe a final value; they do not update the stored
value until confirmation. Callers therefore combine deltas per usage row
before staging them. Interface clearing combines direct and routed addresses
across a VPS, including soft and hard deletion. Clone already combines its
interface allocations. Migration retains its existing rejection of multiple
interfaces.

## Disownership

Disowning an IP keeps its owner and quota until asynchronous DNS transfer,
PTR and user-created host cleanup has confirmed successfully. Failed cleanup
or rollback retains ownership and accounting. With no asynchronous cleanup,
disownership remains immediate. The existing API transaction-state metadata
identifies pending work; callers must await success before relying on release.
The WebUI's combined disown-and-remove action waits before removing the route
and keeps it when disownership is pending or failed.

Account teardown links IP cleanup before quota destruction. It refuses owned
allocations with missing charge provenance so accounting evidence remains
available for reconciliation. The account's quota records remain until cleanup
has completed.

If disownership remains pending or fails, the WebUI keeps the route and links to
its transaction. Submit removal again after completing or resolving that chain.
See [pending-chain recovery](ip-ownership-operations.md#pending-chains) for
operator intervention.

## Batch disowning

`TransactionChains::Ip::Disown` owns cleanup and disown accounting for both
ordinary `Ip::Update` and campaign releases. It groups allocations by owner,
recorded charge environment and resource and calls `adjust_resource!` once per
group. Deferred confirmations contain absolute totals: calculating the same
usage row separately for each IP would overwrite earlier deltas. The helper
reserves current allocations and accounting rows in order and returns the final
confirmation so a campaign can attach release markers to the same operation.
Campaigns pass `defer: true`, retaining all ownership until the whole chain
succeeds, including allocations without asynchronous cleanup. Ordinary single-IP
updates preserve their immediate no-cleanup behavior.

## Charge provenance and network registration

Every owned allocation needs a recorded `charged_environment_id`. Registration
and managed-network additions record the charge environment; managed additions
require the owner and environment together. Assignment and disownership reject
owned addresses without that provenance. Campaign release fails preparation for
the whole selected batch, keeping ownership and quota until reconciliation.
Account deletion retains the accounting evidence needed for the same repair.

The recorded environment identifies where an allocation is charged. It does not
prove that the resource type implied by the current network matches the original
charge. Public IPv4, private IPv4 and IPv6 have different accounting resources.
Current network locations also cannot establish an old allocation's charge
identity. Use the [accounting audit and reconciliation procedure](ip-ownership-operations.md#accounting-audit-and-reconciliation)
when provenance or historical network semantics are uncertain.

Network role and IP version cannot change while the network contains IP
allocations. Registration takes the same network row lock as this validation,
including registration of the first address. Converting a populated network
requires a separate audited maintenance operation that reconciles accounting;
ordinary `Network.Update` does not perform that conversion.

## Purpose filters

`Network.Index`, `IpAddress.Index` and `HostIpAddress.Index` accept an exact
`purpose` filter and a compatibility filter, `usable_for`. The latter accepts
`vps` (network purposes `any` or `vps`) and `export` (`any` or `export`). Both
filters intersect when supplied together. Omitting them leaves network purpose
unrestricted.

Compatibility describes the network's permitted use. It does not establish that
an address is unassigned or available for allocation. Other query filters and
caller visibility still apply. Filtering happens before pagination and counts.
The WebUI's Networking and DNS address lists and selectors request
`usable_for=vps`, so they include general-purpose networks and omit export-only
networks.

An included address can already belong to an export interface. Address details
show its interface without a VPS link or VPS assignment controls.
`NetworkInterface.Show` permits administrators and the interface's VPS or export
owner to read these details. Interface listing and updates remain VPS operations;
direct IP and host-address visibility rules are unchanged. Host details can
expand an export owner's allocation metadata even when the allocation is
unowned. This association permission does not grant direct IP listing or access
to another user's export.
