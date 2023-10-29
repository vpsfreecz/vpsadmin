# nodectl 1                         2022-11-04                             3.0.0

## NAME
`nodectl` - remote control for nodectld

## SYNOPSIS
`nodectl` *command* [`-pvh`] [`-s` *socket*] *...*

## DESCRIPTION
`nodectl` interacts with nodectld. It can view its status, reload configuration,
control its lifetime and more.

`nodectl` needs nodectld to be running and with enabled remote control at all
times except for using `-h` or `-v`.

nodectld must be started using system init script or manually, `nodectl` cannot
start it.

## COMMON OPTIONS
`-p`, `--parsable`
  Use in scripts, output can be easily parsed.

`-s`, `--socket` *socket*
  Connect to specified socket instead of default `/run/nodectl/nodectld.sock`.

`-v`, `--version`
  Print version and exit.

`-h`, `--help`
  Show help and exit.

## COMMANDS
`ping`
  Check if nodectld is alive.

  Writes `pong` to stdout and exits with return code `0` on success.

`status` [*options*]
  Show nodectld's status. If no option is specified, a summary is shown.

    `-H`, `--no-header`
      Do not print the header row, useful for scripts.

    `-c`, `--consoles`
      List exported consoles. Consoles are exported when accessed from vpsAdmin
      web interface.

    `-t`, `--subtasks`
      List subprocesses that block further execution of specific transaction chains.

    `-w`, `--workers`
      List transactions and commands that are currently being run.

`pause` [*id*]
  Pause execution of queued transactions. Running transactions are finished, new
  transactions are not executed until `nodectl resume` is called.

  Argument *id* is optional. If used, execution will be paused after transaction
  with id *id* is finished. Until then, new transactions are normally executed.

  `pause` stops the execution of urgent transactions, too.

  `pause` returns immediately. It does not wait for the pause to take effect.

`resume`
  Resume transaction execution after it has been paused by `nodectl pause`.
  `resume` cancels both immediate and delayed pause.

  `resume` can also be used to cancel scheduled stop, restart or update.

  `resume` returns immediately.

`queue pause` *name* [*seconds*]
  Pause queue *name* either until `resume` is called, or number of *seconds*
  pass.

`queue resume` *name*|`all`
  Reopen queue *name* or all queues.

`queue resize` *name* *new-size*
  Resize queue *name*. It is the same as using
  `nodectl set config vpsadmin.queues.<name>.threads`=*new-size*.

`restart` [`-f`]
  Order nodectld to restart. nodectld will wait for transactions that are running
  to finish. It will not execute more transactions.

  `nodectl` does not wait for the restart to finish, it returns immediately.

    `-f`, `--force`
      Restart nodectld immediately, do not wait for transactions to finish.
      All transactions are softly killed and will restart when nodectld is started.

`stop` [`-f`]
  Order nodectld to exit. nodectld will wait for transactions that are running
  to finish. It will not execute more transactions.

  `nodectl` does not wait for the stop to finish, it returns immediately.

    `-f`, `--force`
      Stop nodectld immediately, do not wait for transactions to finish.
      All transactions are softly killed and will restart when nodectld
      is started later.

`chain` *id* `confirmations` [*transaction_id...*]
  List transaction confirmations.

`chain` *id* `confirm` [*transaction_id...*]
  Run transaction confirmations.

    `--direction` *direction*
      Set direction in which the confirmations should be run. *direction* can be
      `execute` or `rollback`.

    `--[no]-success`
      Decide whether the confirmations should be run as if the transaction succeeded
      or not.

`chain` *id* `release` [`locks`|`ports`]
  Release resource locks, reserved ports or both.

`chain` *id* `resolve`
  Mark the chain as resolved.

`chain` *id* retry [*transaction_id*]
  Rerun transaction chain, either from the beginning or from *transaction_id*.
  All or transactions up from and including *transaction_id* are marked as queued
  and executed again.

  This command is intended to be used on transaction chains that end up in state
  `fatal`.

`reinit` `shaper`|`all`
  Reinitialize resources. resource may be one of `shaper` or `all`.
  The reinitialization is an atomic operation.

  See `nodectl init` and `nodectl flush` for more information.

  `nodectl` blocks until reinit is finished.

`flush` `shaper`|`all`
  `shaper` flushes shaping rules from kernel by `tc`.

`init` `shaper`|`all`
  `shaper` will initialize shaping rules by `tc`.

`get` *subcommand...*
  Access nodectld's resources and properties. When used with option `-p`, output
  is formatted and printed in JSON.

  Common options:

    `-H, `--no-header`
      Suppress the header row.

    `-l`, `--limit` *n*
      Limit numer of listed queued transactions to *n*. Defaults to `50`.

`get config` [*key*]
  Read and print config. If no argument is specified, print the whole config.

  Using argument *key*, you can select only specific part of tje config to be
  printed. Nested keys are separated by `.`.

`get` `queue`
  List transactions queued for execution. Transactions whose dependencies are
  not met yet are not listed, as it is impossible to know when they will be executed.

`get veth_map`
  Print veth map contents, listing all known VPS interfaces and their names on
  the host.

`get net_accounting`
  Print network interface accounting state, listing all tracked interfaces
  and their counters.

`set config` *key*`=`*value*...
  Alter nodectld's configuration. Set *key* to *value*. Format of keys is the same
  as for `get`. Multiple keys may be specified, separated by spaces.

`reload`
  Instructs nodectld to reload its configuration file.

  `nodectl` does not wait for the reload to actually finish, although it happens
  instantly.

`kill` [[`-a`] | [`-t`]] [*id*|*type*]...
  Kill selected running transactions. This command accepts a list of transaction
  ids or types. Arguments are by default treated as transaction ids. Option `-t`
  changes that to transaction type.

  This command does not kill transactions waiting in queue, only those which are
  currently running.

  Transactions are marked as failed, their error message set to "Killed".

  `nodectl` blocks until all matching transactions are killed.

    `-a`, `--all`
      Kill all running transactions, you do not have to provide list of ids or types.

    `-t`, `--type`
      Arguments are transaction types, not ids.

`refresh`
  Update info about this node, including kernel version, and all its VPSes
  and datasets. Traffic accounting is not updated.

  `nodectl` blocks until refresh is finished.

`incident-report pid` *pid...*
  Report incident to VPS that the given PIDs belong to. `nodectl` identifies
  the processes and opens `$EDITOR` with incident report content, which the user
  can edit. When `$EDITOR` is closed and the file is not empty, the incident
  reports are sent to users.

  Given PIDs may belong to different VPS, incident reports are sent to each one.

`incident-report vps` *vps...*
  Open `$EDITOR` to create an incident report on given VPS. When `$EDITOR` is
  closed and the file is not empty, the incident reports are sent to users.

`pry`
  Open remote console from nodectld.

  The session can be closed with `^D`, `quit` or `exit`.

`halt-reason`
  Look up possible maintenances/outages reported in vpsAdmin that could be used
  as a reason for `halt`/`poweroff`/`reboot` of this node. The reason is wrote
  to the standard output, which is meant to be processed by halt reason template
  configured in vpsAdminOS option `runit.halt.reasonTemplates` by the nodectld
  module.

## EXAMPLES
Check how nodectld is doing:

  `nodectl status`

Show what transactions and commands are running at the moment:

  `nodectl status -w`

Kill two transactions you want to cancel. `1234` and `5678` are transaction ids:

 `nodectl kill 1234 5678`

Kill all transactions:

  `nodectl kill -a`

Read server ID:

  `nodectl get config vpsadmin.server_id`

Change number of concurrent workers of the `zfs_send` queue:

  `nodectl set config vpsadmin.queues.zfs_send.threads=10`

Confirm change:

  `nodectl get config vpsadmin.queues.zfs_send.threads`

See what transactions are queued and will be executed, limit count to `10`:

  `nodectl get queue -l 10`

## BUGS
Report bugs to https://github.com/vpsfreecz/vpsadmin/issues.

## ABOUT
`nodectl` is a part of [vpsAdmin](https://github.com/vpsfreecz/vpsadmin).
