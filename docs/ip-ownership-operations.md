# IP ownership operations

The [ownership guide](ip-locking.md) defines charge provenance, reservation and
cleanup guarantees for IP and network operations. Use these procedures when
historical accounting needs reconciliation or a transaction needs operator
recovery. A release campaign uses the same ownership and accounting rules.

## Accounting audit and reconciliation

Before releasing or transferring allocations with uncertain accounting history,
audit populated networks' role and IP family against allocation and accounting
records. Older APIs allowed these fields to change on populated networks. A
non-null charge environment does not prove that the address was charged to the
resource implied by its current network.

Verify the network address family and affected owners' environment usage for
public IPv4, private IPv4 and IPv6. Use reliable operation or maintenance records
to establish prior network changes. If the history is ambiguous or usage does
not agree, reconcile the affected allocations and quota before releasing or
transferring them. The campaign migration does not infer or repair historical
resource types.

Find owned allocations with missing charge identity:

```sql
SELECT ip.id, ip.ip_addr, ip.prefix, ip.user_id, ip.network_id,
       GROUP_CONCAT(DISTINCT l.environment_id ORDER BY l.environment_id) AS available_environments
FROM ip_addresses ip
LEFT JOIN location_networks ln ON ln.network_id = ip.network_id
LEFT JOIN locations l ON l.id = ln.location_id
WHERE ip.user_id IS NOT NULL AND ip.charged_environment_id IS NULL
GROUP BY ip.id, ip.ip_addr, ip.prefix, ip.user_id, ip.network_id;
```

`available_environments` lists current network locations for diagnosis. It is
not evidence of where the allocation was charged, even when it contains only
one environment. Older registration paths and the original multi-location
migration left some unassigned owned addresses without charge identity.

For each affected allocation:

1. Reconcile the owner's environment quota usage against allocation history.
   Establish both the charged environment and the correct resource type. Leave
   the allocation blocked if the available records cannot establish them.
2. In an audited administrator maintenance session, set
   `charged_environment_id` to the verified environment. Preserve quota usage
   when correcting only this missing identity. Reconcile an actual accounting
   discrepancy separately; do not apply another charge just to fill the field.
3. Repeat the missing-identity query and verify the affected owners' usage
   against the reconciled history before retrying the original operation.

Assignment and release reject owned allocations with missing provenance.
Campaign preparation failure leaves the whole selected batch owned and charged.
Account deletion waits for reconciliation and retains its quota records while
IP cleanup is pending. Preserve those records during maintenance.

Populated-network conversion requires a separate audited maintenance operation
that reconciles the affected allocations and quota. Changing the network role
or IP family alone is insufficient; ordinary `Network.Update` rejects it.

## Pending chains

Inspect the transaction-state metadata returned by an IP operation. Ordinary
disownership retains owner and quota until asynchronous DNS-transfer, PTR and
user-created host cleanup succeeds. The combined WebUI disown-and-remove action
keeps the route while that work is pending or failed. After completing or
resolving the chain, submit removal again.

For a campaign, inspect its release attempt and linked transaction chain before
retrying. Preparation failure creates no release chain. A successful rollback
keeps the batch owned and charged; the administrator can initiate a new attempt
once the failure is resolved. An active attempt is reused by repeated release
submissions, and closing the campaign does not cancel it.

A fatal chain or a resolved chain whose release confirmation is incomplete
requires operator attention. Keep its reservations and reconcile its commands,
rollback and database confirmations before admitting another release attempt.
Do not clear locks or manually confirm individual IP releases to bypass this
state. Recovery must preserve the batch's combined ownership, quota and release
markers. See [campaign release outcomes](ip-release.md) and
[transaction confirmations](transactions.md) for the application semantics.

Before reverting deployed software, follow the
[upgrade guide's rollback procedure](upgrade-ip-ownership-reservations.md#software-rollback).
