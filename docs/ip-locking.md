# IP ownership and assignment locks

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
IP reservation protocol. Roll out compatible API and supervisor writers and
finish older in-flight chains before enabling release campaigns. This does not
change the node protocol or the stored resource-lock format.

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
