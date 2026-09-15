# Architecture overview

vpsAdmin manages virtual servers, storage, and networks on
[vpsAdminOS](https://github.com/vpsfreecz/vpsadminos). The API owns business
logic, access control, and the database representation of the cluster. Node
daemons apply changes to containers and storage.

## Components

| Component | Responsibility |
| --- | --- |
| [API](../api/) | Exposes the HaveAPI interface, validates requests, and prepares transaction chains. |
| [Web UI](../webui/) | Provides the PHP web interface to the API. |
| [Client](../client/) | Provides the Ruby client and `vpsadminctl` command. |
| [nodectld](../nodectld/) and [libnodectld](../libnodectld/) | Execute transactions and report node, VPS, and storage status. |
| [nodectl](../nodectl/) | Provides operator commands for the node daemon. |
| [Supervisor](../api/lib/vpsadmin/supervisor/) | Receives node reports and handles RPC requests through RabbitMQ. |
| [Scheduler](../api/lib/vpsadmin/scheduler/) | Runs scheduled tasks. |
| [Console router](../console_router/) | Connects web and CLI consoles to the appropriate node. |
| [Download mounter](../download_mounter/) | Mounts snapshot download directories for an HTTP server to serve. |

The [NixOS modules](../nixos/modules/vpsadmin/) configure these services.
[Package definitions](../packages/) build the components for deployment.

## From an API request to a node operation

A request that needs work on a node, such as starting a VPS or transferring a
snapshot, creates a [transaction chain](transactions.md) in MariaDB. Each
transaction identifies its node, command, and dependency. `nodectld` polls the
database for work it can execute and writes results back to the database.

Transaction confirmations connect database changes to the outcome of node
operations. For example, a newly created dataset remains unconfirmed until
the chain completes successfully. Resource locks prevent conflicting chains
from changing the same object concurrently.

Node status reports and RPC use RabbitMQ. They complement the database-backed
transaction queue: reports update the API's view of running infrastructure,
while transactions record requested work and its outcome.

## Relationship with vpsAdminOS

vpsAdminOS provides the container host, including `osctld`, the `osctl` command,
and ZFS storage. `nodectld` uses those facilities to execute vpsAdmin work.
The host platform also supports use without vpsAdmin.

Keep account policy, database relationships, backup ownership, and cluster
orchestration in vpsAdmin. Host operations exposed by vpsAdminOS should remain
usable independently of this control panel.

A node can host VPSes, provide storage, or perform other configured cluster
roles. [Storage pools](storage/README.md) distinguish VPS storage, primary
shared storage, and backups. [Plugins](plugins.md) extend the API with features
such as payments and outage reporting.
