# Snapshot downloads and local backups

vpsAdmin exports dataset snapshots as gzip-compressed tar archives or ZFS
streams. A `SnapshotDownload` records the export format, source snapshot,
URL, preparation status, checksum, and expiration.

## Formats and incremental history

| API format | Content |
| --- | --- |
| `archive` | Files from a snapshot in a `.tar.gz` archive. |
| `stream` | A full ZFS send stream compressed with gzip. |
| `incremental_stream` | A gzip-compressed incremental ZFS stream from `from_snapshot` to the selected snapshot. |

Incremental downloads require snapshots from the same dataset with matching
`history_id` values and a usable source for the pair. The base snapshot must
precede the target. `Dataset.current_history_id` identifies the current
history, while each snapshot has its own `history_id`.

Reinstall and branching can change the history identifier. Existing snapshots
can acquire a new identifier during rollback, so clients must refresh these
values instead of treating them as permanent snapshot properties. Separate
histories require separate full transfers.

Source: [download resource](../../api/lib/vpsadmin/api/resources/snapshot_download.rb),
[incremental source selection](../../api/models/transaction_chains/dataset/incremental_download.rb),
and [branching](branching.md).

## Preparing and serving an export

The API selects a source pool and creates the download transaction. The node
writes the export under that pool's `vpsadmin/download` dataset. A random
100-character hexadecimal key forms part of the download URL. Treat the URL
as a secret: anyone who obtains it can retrieve the file when the HTTP server
serves downloads without additional authentication.

`vpsadmin-download-mounter` mounts the pool download directories over NFS
under a common root. The deployment must configure the HTTP server and set
`core.snapshot_download_base_url` to its base URL. The download model appends
the node's fully qualified domain name, pool ID, secret key, and file name.
The [download-mounter NixOS module](../../nixos/modules/vpsadmin/download-mounter.nix)
configures the mounting service.

Each download dataset contains `_vpsadmin-download-healthcheck` with its
numeric pool ID. The mounter checks this file to detect stale or incorrect
mounts; the same file can check the HTTP serving path.

Source: [download model](../../api/models/snapshot_download.rb),
[preparation chain](../../api/models/transaction_chains/dataset/base_download.rb),
[node export command](../../libnodectld/lib/nodectld/commands/dataset/download_snapshot.rb),
and [download mounter](../../download_mounter/lib/vpsadmin/download_mounter/mounter.rb).

## Completion and streaming

The URL is available before the export finishes. `ready` becomes true when
the download is confirmed. Before then, `size` is an estimate; afterward it
contains the completed file size in whole MiB. It is not an exact byte count.
`sha256sum` is the SHA-256 checksum of the compressed file.

A client can download while the node is still writing the file by using HTTP
range requests and checking `SnapshotDownload` between requests. An early end
of an HTTP response does not prove completion. Wait for `ready`, fetch the
remaining bytes, and verify the checksum. An initial HTTP 404 can mean that
preparation has not started; loss of the API download record or disappearance
of a file after transfer began must be treated as a failed download.

The Ruby client's [stream downloader](../../client/lib/vpsadmin/cli/stream_downloader.rb)
implements this polling and checksum verification. Download records have an
expiration date; lifetime processing removes expired exports.

## CLI commands

These commands use an authenticated `vpsadminctl` client. `SNAPSHOT_ID`,
`DATASET_ID`, `VPS_ID`, and `FILESYSTEM` below are placeholders.

| Command | Behavior |
| --- | --- |
| `vpsadminctl snapshot download SNAPSHOT_ID` | Saves the compressed export to a file; the default format is `archive`. |
| `vpsadminctl snapshot send SNAPSHOT_ID` | Writes a decompressed ZFS stream to standard output. |
| `vpsadminctl backup dataset DATASET_ID FILESYSTEM` | Maintains a local ZFS backup of a remote dataset. |
| `vpsadminctl backup vps VPS_ID FILESYSTEM` | Selects the VPS root dataset and uses the same local backup mechanism. |

`snapshot download` accepts `--format`, `--output`, and `--resume`.
`--output=-` writes the compressed file to standard output. `snapshot send`
accepts `--from-snapshot` for an incremental stream. Both commands verify the
compressed-file checksum and delete the server export after a successful
download by default; `--no-delete-after` retains it until removal or expiration.
`snapshot download` can select a snapshot interactively when run in a terminal
without an ID.

Local backup commands use child datasets named by history identifier and
store the remote dataset ID in the `cz.vpsfree.vpsadmin:dataset_id` ZFS
property. Later runs can omit the remote ID and use that property. Without a
stored ID, the client offers an interactive selection.

Use a dedicated local dataset for each backup. The commands receive ZFS
streams and rotate local snapshots by default. `--pretend` prints the planned
work; `--no-rotate` disables automatic snapshot rotation. History identifiers
allow a new full receive after a remote history change while keeping earlier
local histories subject to retention.

Source: [snapshot download](../../client/lib/vpsadmin/cli/commands/snapshot_download.rb),
[snapshot send](../../client/lib/vpsadmin/cli/commands/snapshot_send.rb),
[dataset backup](../../client/lib/vpsadmin/cli/commands/backup_dataset.rb), and
[VPS backup](../../client/lib/vpsadmin/cli/commands/backup_vps.rb).
