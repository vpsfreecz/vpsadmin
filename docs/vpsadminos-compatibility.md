# vpsAdminOS compatibility

vpsAdmin uses vpsAdminOS to manage containers on nodes. The supported combination
includes the running daemon and the persistent state it manages. Being able to
parse a pool's YAML or boot an older system generation does not establish that
the older daemon preserves its recovery guarantees.

## Recovery metadata

Recovery-aware osctld persists container `recovery_tainted`, saved error state
and veth `host_link` ownership metadata. The link record contains its name,
ifindex, optional IFB ifindex, boot ID and taint. osctld prevents a container from
starting while it or one of its interfaces has recovery taint.

A daemon without these semantics ignores the recovery guard and omits the
metadata when saving configuration. After recovery-aware osctld has managed a
pool, downgrading that pool to a daemon without these semantics is unsupported.
Retain a system generation with recovery-aware osctld and fix problems there.
There is no supported downgrade conversion.

A reboot, restored older YAML, removed metadata or successful cleanup does not
establish downgrade support. Container recovery taint persists separately from
boot-bound host-link records. Resolve incomplete cleanup with the daemon that
understands those guards, and retain diagnostic state if it refuses an operation.
The [osctl recovery-command reference](https://github.com/vpsfreecz/vpsadminos/blob/staging/osctl/man/man8/osctl.8.md)
describes `ct recover cleanup` and the checks that `ct recover forget-host-link`
performs to confirm that the recorded host links are absent. These commands
repair state for the supported daemon; they do not establish downgrade support.

## Inputs, deployment and runtime files

Updating vpsAdmin's `flake.lock` selects vpsAdminOS for subsequent builds. It does
not deploy node configurations, replace a running kernel or rebuild existing
guests. Nodes adopt the selected generation through their normal deployment
process, and guest configuration changes have their own activation requirements.
Keep kernel and OpenZFS generations paired, following the
[vpsAdminOS update guide](https://github.com/vpsfreecz/vpsadminos/blob/staging/docs/os/updates.md).

Older monitoring code can ignore the separate container-state history and
nodectld boot-obligation ledger files under `/run`. That file compatibility does
not remove recovery-metadata restrictions or establish an older osctld as a safe
rollback target. [Boot monitoring](boot-autostart.md) documents its own enrollment
and failure semantics. Consult the [upgrade guides](upgrades/README.md) for the
source and target revisions of a supported transition.
