# Node RPC and recovery

NodeCtld uses [RpcClient](../libnodectld/lib/nodectld/rpc_client.rb) for requests
to the API through RabbitMQ. Each client owns an exclusive reply queue, a
channel and its local consumer. [NodeBunny](../libnodectld/lib/nodectld/node_bunny.rb)
coordinates their lifecycle with Bunny's automatic connection recovery.

## Error ownership

`RpcClient.run` records exceptions from its own construction or body and closes
the constructed client in `ensure`. A pending exception keeps its object and
backtrace when cleanup also fails. An exception handled by the caller's enclosing
rescue does not count as this invocation's failure. A body that re-raises that
same exception does count. The secondary diagnostic contains the cleanup
exception class. Successful bodies keep their return value when cleanup succeeds,
including a nonlocal `return` or `break`.

When cleanup is the only failure, a known transport failure raises
`RpcClient::CleanupError`, with the original cleanup exception as its cause.
`RpcClient::TransportError` identifies known transport failures during setup or
publication; `RpcClient::Timeout` retains its response-timeout meaning.
Programming errors, permanent broker refusals and signals propagate instead of
becoming temporary transport errors. Network wrappers are classified by their
underlying cause, and transport classification applies only to Bunny calls.
Without a pending constructor or body exception, cleanup failure also interrupts
a nonlocal return or break under Ruby's normal ensure rules.

Close is synchronized and one-shot. Its first caller attempts queue deletion
and channel close. Subsequent callers perform no broker I/O. A failed close
makes the client unusable, even if retirement is still pending. Failed partial
constructors also retire their allocated channel, including the last setup
attempt.

## Ambiguous acknowledgements

A timed-out queue deletion or channel close may still receive a late broker
acknowledgement. Bunny 2.24 uses a connection continuation for channel open and
close, so issuing another operation or reusing a channel number before closing
the old transport can consume the wrong acknowledgement.

NodeBunny serializes application setup and cleanup under the same lifecycle
lock. A failed operation registers retirement before releasing that lock and
closes the publication gate. It stops issuing methods on the affected channel;
queue deletion timeout does not lead to a second channel-close request.

Each retirement token refers to the exact channel object and its old transport
and reader. Completion requires all of the following:

- Actual old transport closure, checked after Bunny's close operation.
- The old reader stopped and joined, or at its own network-recovery boundary.
- The channel's consumer workers stopped and joined, including workers whose
  pool already reports `running? == false`.
- Exclusion of that exact channel from Bunny's recovery registry.

Bunny then recovers surviving channels. Creation and required publication wait
until recovery and pending retirements finish; optional publication drops while
the gate is closed. A late retirement stays pending or forces the next existing
recovery cycle. An unrelated generation increment cannot acknowledge its token.
Completed entries leave the pending registry. Repeated requests for the same
channel share its token.

The lifecycle lock precedes short recovery-state monitor sections. Recovery
callbacks never acquire the lifecycle lock, and the monitor is not held across
broker calls, transport close or worker joins. Publication can initiate recovery
on its own thread without deadlocking that gate.

Channel lifecycle and retirement waits use a 30-second monotonic budget. RPC
publication explicitly selects that budget through NodeBunny's internal
`recovery_timeout` keyword, even without a stop predicate. Ordinary required
publishers wait without a gate deadline through recovery or contention with
another publisher. Optional publication still drops while the gate is closed.
The internal timeout and stop keywords never reach Bunny's message properties.

Timeout leaves retirement owned and the gates closed. Callers can pass a
cooperative `stopped` predicate to `RpcClient.run`; retry and condition waits
check it at least once per second and raise `RpcClient::Stopped`. Unbounded
publisher gate waits also observe a supplied stop predicate. Stop does not
discard retirement or start another recovery thread. Each opted-in gate wait
has its own budget; existing transport retries and synchronous Bunny I/O bounds
still apply. This does not impose a hard deadline on the whole RPC call or
whole-daemon shutdown.

## Storage telemetry

`StorageStatus` builds a complete replacement catalog locally. RPC failure,
including cleanup failure after a successful body, keeps the exact previous
pool view and does not enqueue a success-triggered read. The updater logs a
bounded warning and tries again at the normal update interval. A later successful
fetch replaces the view atomically.

Periodic reads and submissions can continue against the previous catalog. They
are stale membership and do not establish that the latest API refresh succeeded.
Catalog parsing, ZFS reads and telemetry writes stay outside the updater's RPC
exception boundary. Stop prevents another fetch or publication of a completed
post-stop refresh.

## Compatibility and verification

The API/Node RPC wire and database schema are unchanged. Ordinary Node service
restart selects the new code. Reverting code restores the defect and does not
repair a transaction chain interrupted by an earlier daemon failure. Diagnose
that chain under its normal recovery procedure; these changes do not authorize
manual unlock or replay.

The focused Node specs cover exception precedence, partial construction,
continuations, registry exclusion, worker termination, recovery gates and stale
telemetry. The `storage/restore-after-reinstall-remote` scenario checks persistent
test queue delays after graceful restart and actual snapshot/restore contents.
It does not establish transaction recovery from a live-transfer crash.
