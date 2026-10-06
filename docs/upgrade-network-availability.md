# Upgrade to network availability controls

This guide applies when upgrading from a schema before migration
`20261006120000_add_network_enabled` to a version that enforces
`Network.enabled`. The [IP locking documentation](ip-locking.md#network-availability)
owns the admission and continuity contract.

The migration adds a non-null boolean column with default true. Existing networks
and creates that omit the field stay enabled. Updates that omit it preserve the
current state. The migration changes no routes, owners, resource-lock format or
node protocol and requires no coordinated node update.

Apply the migration before starting the enforcing API. Replace every old API
instance and other allocation writer before disabling any network: old writers
ignore the column and can allocate from a disabled pool. Mixed versions are
safe only while every network remains enabled. Review site-specific allocation
writers as well as the normal API. Operations already accepted may finish after
a network is disabled.

Deploy the administrator interfaces after the API and refresh their normal API
description caches. New interfaces expose controls only when action metadata
advertises the field. An older interface can continue ordinary operations but
cannot manage availability. Existing clients can omit the additive field; they
need updated discovery or bindings to manage it.

Re-enabling a network restores new use through the normal administrator update.
Rolling back only the UI preserves enforcement. Rolling back to an API that
ignores availability is unsafe while any network is disabled. Retain enforcing
writers, or stop new-allocation writers and explicitly resolve disabled-network
policy before restoring older code. Do not silently re-enable retired pools.
The schema rollback removes the column and its policy; it does not remove
addresses, ownership or assignments. Dropping it is not routine recovery.
