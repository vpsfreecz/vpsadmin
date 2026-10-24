# Boot autostart inventory RPCs

The node-authenticated supervisor RPC interface provides boot inventory and
authoritative reconciliation for nodectld's boot autostart monitor. These are
internal RPCs, separate from the member API. They do not change
`list_vps_status_check` or require a database migration.

`list_vps_boot_autostart()` returns one complete inventory:

```json
{"schema_version":1,"vpses":[{"id":101,"pool_fs":"tank/vps"}]}
```

Rows are sorted by integer VPS ID and contain confirmed, active or suspended,
autostart-enabled VPSes assigned to the requesting node. The result includes
VPSes without a running container or imported pool: those are still expected
at boot. Empty inventory is valid. A missing dataset/pool association, a pool
on another node, or an invalid pool filesystem fails the entire RPC with
`inventory_invalid`; it never silently removes a boot obligation. Filesystem
names are nonempty slash-separated ZFS name components, without whitespace,
empty components, or components equal to `.` or `..`.

`reconcile_vps_boot_autostart(ids)` accepts 1–1000 sorted, unique, positive
integer IDs. The caller batches larger cohorts. Its response contains exactly
one row for every requested ID in that order:

```json
{"schema_version":1,"vpses":[
  {"id":101,"disposition":"retain","reason":"expected","pool_fs":"tank/vps"},
  {"id":102,"disposition":"retain","reason":"resource_locked","pool_fs":null},
  {"id":103,"disposition":"retire","reason":"assigned_elsewhere","pool_fs":null}
]}
```

Each request reads its data in one SQL statement. Reconciliation joins requested
identities to unscoped VPS rows, pool associations and `Vps` resource locks in
the same database snapshot. This includes locks whose VPS row is absent and
avoids combining a pre-confirmation VPS state with a post-release lock lookup.
See [transaction locks and confirmations](transactions.md).

The first matching condition determines the result:

| Condition | Disposition | Reason |
| --- | --- | --- |
| A `Vps` resource lock exists, including an unassigned or fatal-chain lock | `retain` | `resource_locked` |
| VPS row is absent and unlocked | `retire` | `deleted` |
| VPS row is not confirmed | `retain` | `transitional` |
| Confirmed VPS is assigned to another node | `retire` | `assigned_elsewhere` |
| Confirmed VPS is outside active/suspended state | `retire` | `inactive` |
| Confirmed VPS has autostart disabled | `retire` | `autostart_disabled` |
| Expected VPS has an invalid dataset/pool association | `unknown` | `inventory_invalid` |
| Otherwise | `retain` | `expected` |

Only `retain/expected` includes `pool_fs`; every other row has `pool_fs:null`.
Foreign node IDs, owners, hostnames and other VPS details are not returned.
The consumer compares the current expected pool with its frozen boot pool; a
pool change retires the original obligation without enrolling a new one.

An omitted row, RPC failure or unknown result is not retirement evidence.
The consumer retains pending obligations when it cannot establish a complete,
valid response. Independently recorded successful running can fulfil an
obligation even during an RPC outage. Resource locks remain conservative until
released; a fatal transaction does not silently clear a genuine boot failure.

Deploy the additive supervisor provider before the nodectld consumer. Old nodes
continue using their existing RPCs; a consumer facing an old supervisor must
report unavailable monitoring rather than assume empty inventory. The RPCs
write no state, so a provider rollback leaves ordinary VPS data unchanged.
