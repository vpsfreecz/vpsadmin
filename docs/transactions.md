# Transactions

Transactions record work that must run on a node, such as starting a VPS or
creating a ZFS snapshot. A transaction chain groups the steps of an operation;
the steps can run on different nodes and depend on earlier steps in the chain.
These application transactions are separate from database transactions.

## Creating and executing a chain

The API creates chains through `TransactionChain.fire`. The chain's
`link_chain` method acquires resource locks and appends transactions. Chain
construction runs inside a database transaction: if preparation fails, its
database changes are rolled back. A prepared chain becomes `queued`.

Each transaction contains its command handle, node, parameters, and dependency.
The API signs the command input. The node verifies the signature and its
binding to the transaction before executing the command.

`nodectld` polls MariaDB for queued transactions assigned to its node. A step
becomes eligible after its dependency finishes. The daemon records command
results, advances the chain, and makes subsequent steps available. Higher
numeric priorities are selected first, with transaction IDs breaking ties.

Source: [chain construction](../api/models/transaction_chain.rb),
[transaction input](../api/models/transaction.rb),
[node scheduling](../libnodectld/lib/nodectld/daemon.rb), and
[signature verification](../libnodectld/lib/nodectld/transaction_verifier.rb).

## Queues and concurrency

Transactions select a queue, such as `general`, `storage`, `vps`, `zfs_send`,
or `zfs_recv`. Each queue has configured worker capacity, additional urgent
capacity, and an optional startup delay. An urgent transaction still needs an
available slot.

Chains can reserve queue capacity for operations that must coordinate workers,
including storage transfers. Dependencies order the steps of a chain;
resource locks protect objects shared by different chains. Code that modifies
a VPS or dataset must acquire the corresponding locks.

Source: [transaction queues](../libnodectld/lib/nodectld/transaction_queue.rb).

## Resource locks

A chain owns the locks it acquires. Nested chains share their parent's lock
set, so they can use an object already locked by that parent. Lock acquisition
normally raises `ResourceLocked` when another operation owns the resource;
callers can explicitly request waiting with a timeout.

Locks are released when the chain closes normally, including a completed
rollback. A fatal chain retains its locks for operator investigation. Removing
a lock alone does not reconcile the database with the state of the node.

Source: [Lockable](../api/models/lockable.rb) and
[chain completion](../libnodectld/lib/nodectld/command.rb).

## Confirmations

Confirmations describe database changes whose outcome depends on node work.
They are attached to individual transactions, but the daemon normally applies
them together when the chain finishes execution or rollback. The transaction's
result and the chain's direction determine which changes apply.

| Confirmation | Successful execution | Failure or rollback |
| --- | --- | --- |
| `create` | Mark the prepared row confirmed. | Remove the row. |
| `just_create` | Keep the prepared row without a confirmation field. | Remove the row. |
| `edit_before` | Keep an edit made during preparation. | Restore the recorded original attributes. |
| `edit_after` (also `edit`) | Apply the recorded new attributes. | Leave the attributes unchanged. |
| `destroy` | Delete the row marked for removal. | Restore its confirmed state. |
| `just_destroy` | Delete a row without a confirmation field. | Keep the row. |
| `increment` / `decrement` | Adjust the counter. | Leave the counter unchanged. |

These updates run directly against database tables in the node daemon, so they
do not invoke ActiveRecord callbacks. Chain authors must include the required
node operations and database confirmations explicitly.

Source: [confirmation construction](../api/models/transaction.rb) and
[confirmation execution](../libnodectld/lib/nodectld/confirmations.rb).

## Failure and rollback

A reversible failure can send a chain through its earlier steps in reverse
order. Individual commands supply their rollback implementation. Commands may
also declare an operation irreversible or use `keep_going` to let the chain
continue after that step fails. Reversibility must reflect the actual effect
on node data.

If a rollback command fails, the chain becomes `fatal` and needs operator
attention. Inspect transaction output and actual node state before retrying or
resolving it. Chain state, command results, confirmations, and resource locks
together describe the outcome; an API request being accepted does not mean
that its node operation has completed.
