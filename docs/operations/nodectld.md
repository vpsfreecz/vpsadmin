# Operating nodectld

The NixOS module runs nodectld in minimal mode for services such as mailers and
DNS servers. These services do not need osctld, including when NixOS itself runs
inside a vpsAdminOS container. Minimal mode disables host-container facilities,
including export-mount reporting and VPS OS-release collection, on configuration
load and reload. Standard-mode nodes retain their configured facilities.

## Watchdog and service supervision

The nodectld wrapper monitors transaction-loop progress using a monotonic
clock. The loop reports progress after a successful database poll, or when it
deliberately skips polling because it is paused, draining active work or has
full queues. Only the transaction thread updates this timestamp. A responsive
`nodectl status` alone does not prove that
transactions are progressing: the control thread can respond while the polling
thread is blocked.

The wrapper checks every 30 seconds. After 600 seconds without loop progress
it logs warnings; after 810 seconds it requests the polling thread's
backtrace; after 900 seconds it stops the daemon. Control requests have a
10-second timeout. Shutdown sends TERM, then KILL if the child has not exited
within 60 seconds. These thresholds measure loop progress, not the duration of
an individual transaction. The watchdog leaves a healthy paused loop running;
use `nodectl resume` to resume its work. Pause state is in memory and does not
survive a process restart.

On NixOS, `vpsadmin-nodectld.service` runs this wrapper for every role. systemd
restarts it after five seconds, including a successful wrapper exit during
watchdog recovery. `KillMode=mixed` lets the wrapper stop its child first;
systemd kills any remaining service processes after the 90-second stop timeout.
The vpsAdminOS runit service also runs the wrapper.

Use the service manager to keep nodectld stopped:

```sh
# NixOS
systemctl stop vpsadmin-nodectld.service
systemctl start vpsadmin-nodectld.service

# vpsAdminOS
sv down nodectld
sv up nodectld
```

`nodectl restart` asks the wrapper to replace its daemon child after active work
finishes. `nodectl stop` asks the daemon to exit, but the service manager can
start it again. `nodectl update` refreshes selected VPS information; it does not
update the running software. In minimal mode, OS-release and export-mount
updates are disabled.

## Investigating stalled work

Check both service state and transaction progression. On NixOS, inspect
`systemctl status vpsadmin-nodectld.service` and
`journalctl -u vpsadmin-nodectld.service`. The service's main PID should be the
wrapper, with one daemon child. Verify that its command line has neither
`--no-wrapper` nor `--no-watchdog`. Look for watchdog stale-poll warnings,
transaction-loop backtraces, restart messages and subsequent chain completion.
The control socket is `/run/nodectl/nodectld.sock`. Its newline-delimited JSON
protocol sends a greeting first. A root client can then send
`{"command":"watchdog_debug","params":{}}` and read one response containing
the transaction thread's status and backtrace. Bound the connection and reads
when using this diagnostic interface: a stuck control thread might not answer.
The wrapper uses this same request automatically at the debug threshold.

Keep the logs and any available backtrace before restarting a stalled service.
Use `systemctl restart vpsadmin-nodectld.service` on NixOS or
`sv restart nodectld` on vpsAdminOS. If a stop is still pending, inspect the
service manager and wrapper logs to determine whether child shutdown or the
final kill deadline is in progress.

After recovery, check queued work and the actual service result, such as SMTP
delivery or the DNS change. Restarting cannot guarantee exactly-once external
effects if a process dies between performing work and confirming it in the
database. Follow the [transaction failure semantics](../transactions.md#failure-and-rollback)
before retrying or changing chain state manually.

The generated service unit and daemon package must come from the intended
deployment. Updating only the executable does not change an already generated
unit that bypasses the wrapper. Rollback to such a unit also removes its watchdog
coverage; inspect the effective unit after activation or rollback.

Sources: [minimal-mode policy](../../libnodectld/lib/nodectld/config.rb),
[watchdog thresholds](../../libnodectld/lib/nodectld/transaction_watchdog.rb),
[wrapper](../../nodectld/lib/nodectld/cli.rb), and
[NixOS service](../../nixos/modules/vpsadmin/nodectld/nixos.nix).
