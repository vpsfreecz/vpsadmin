# Dataset plans

Dataset plans attach scheduled work to a `DatasetInPool`. A plan definition in
the API configuration describes group snapshots and backups; an
`EnvironmentDatasetPlan` controls availability and user enrollment in each
environment. Actions have one repeatable task with the schedule described in
[Scheduler](../scheduler.md).
Integer schedule fields are accepted and validated as strings, matching the
stored repeatable task during enrollment, reuse and removal.

```ruby
plan :short_backup, label: 'Short backup', keep_empty_group_snapshots: true do |dip|
  group_snapshot dip, '*/5', '*', '*', '*', '*'
  backup dip, '2-59/10', '*', '*', '*', '*'
end
```

This definition requires a shared snapshot template before enrollment. The
configuration owner must also validate its source pools and exact backup
destination in the plan block. Plans with retained templates require exactly
one open backup copy of the logical dataset. Default plans retain their
first-open destination selection when several backup copies are available.

## Shared snapshot templates

`keep_empty_group_snapshots` defaults to `false`. With that default, enrollment
creates a group action and task as needed, and removal of the last group member
removes them. With `true`, provisioning owns one group action and task for each
`(DatasetPlan, Pool)`. Enrollment adds only the source's plan and group
membership. Removing the last member retains the same action and task. Empty
groups skip execution.

Create the shared action and its compatible task in a separate provisioning
transaction before enabling enrollment. Use the plan's
`with_configuration_lock` block for provisioning and retirement. Do not enroll
a temporary dataset to create the template. The shared rows receive no
creation or deletion confirmations from source chains.

For retained templates, repeat enrollment validates the existing membership,
group member, action, schedule and backup destination, then returns the same
membership. Missing or duplicate rows, incompatible schedules and conflicting
destinations are errors. Provisioning must inspect partial state rather than
delete unexplained rows to make a repeat run succeed.

## Admission, locking and confirmations

Registration, removal and template configuration use the same SQL lock order:
storage admission, the persisted `DatasetPlan` row, then action and task rows.
The Plan lock serializes changes across API processes, including insertion of
an absent template. It remains held until the outer staging transaction commits.
Each operation uses a savepoint when called within another transaction, so an
error discards its provisional membership and task writes.

The common Plan path checks both Dataset and DatasetInPool resource locks,
including direct Dataset Plan API requests. A foreign source lock or a pending
conflicting confirmation refuses the change. A caller may reuse rows owned by
its current transaction chain; pending destructive confirmations still refuse
reuse. An unconfirmed source needs that chain's lock or creation confirmation.
`Transaction::Confirmable#transaction_chain_id` exposes the caller's chain
identity without allowing it to be changed.

New membership and per-source action/task rows use the outer chain's
confirmations. Existing rows and shared templates keep their original ownership.
A provisioning helper must append work to the caller's chain rather than fire
an independent chain while staging. See [Transactions](../transactions.md).

## Configuration compatibility

Load scheduler interval support and the Plan option before introducing a plan
that uses them. Keep the definition available while removing its memberships.
Before returning to code without this option, stop enrollment and scheduling,
wait for pending chains, remove memberships, and retire the empty shared
templates under the same admission and Plan lock. This metadata retirement does
not remove dataset or backup payloads.

Source: [Plan implementation](../../api/lib/vpsadmin/api/dataset_plans.rb),
[Dataset Plan API](../../api/lib/vpsadmin/api/resources/dataset.rb), and
[DatasetAction](../../api/models/dataset_action.rb).
