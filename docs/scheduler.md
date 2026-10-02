# Scheduler

The scheduler loads `RepeatableTask` rows and checks their schedules once per
minute. Each action has one task row. Its cron fields support these forms:

| Form | Meaning | Minute example |
| --- | --- | --- |
| `*` | Every value in the field | Every minute |
| Integer | One value within the field bounds | `15` |
| `*/step` | Every step, starting at the field minimum | `*/5`: 0, 5, ..., 55 |
| `start-end/step` | Inclusive range, starting at `start` | `2-59/10`: 2, 12, ..., 52 |

Ranges cannot wrap. Steps must be positive and no larger than the number of
values in the field. Bounds are 0..59 for minutes, 0..23 for hours, 1..31 for
days, 1..12 for months and 0..6 for weekdays. Comma lists and plain ranges
without a step are unsupported. Invalid values reject the task reload and
log the offending row ID; the scheduler keeps the previous complete task set.

## Task reloads

The scheduler reloads tasks every 10800 seconds by default. NixOS deployments
can set a shorter interval, for example:

```nix
vpsadmin.api.scheduler.taskRefreshInterval = 60;
```

The executable also reads `SCHEDULER_TASK_REFRESH_INTERVAL`, a positive number
of seconds. The NixOS module sets it from the option above.

`vpsadmin-schedulerctl <socket> update` requests an immediate reload without
restarting the scheduler. `vpsadmin-schedulerctl <socket> get-tasks` returns
the loaded schedules. The NixOS module uses `<stateDirectory>/scheduler.sock`.
A `run-task` reply acknowledges queueing; it does not prove that the resulting
transaction chain completed. Resource locks and terminal chain results remain
the authority for snapshot and backup completion.

All scheduler processes must support interval syntax before tasks use it.
Before rolling back to an older scheduler, remove those schedules or replace
them with fields that the older version supports.
