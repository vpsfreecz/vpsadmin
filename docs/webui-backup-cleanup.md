# PHP WebUI backup cleanup

The dataset editor places the administrator cleanup form immediately below the
Backup plans form when the API advertises `Dataset.DisableBackups`. It remains
available with no plans. The plan-removal explanation is inside Backup plans.
VPS backups links to the same confirmation with the VPS root dataset. Ordinary
plan removal keeps its existing behavior and explains that primary and backup
snapshots remain.
The action removes the selected datasets from all backup plans and deletes their
local snapshots; shared plan definitions and other datasets' memberships remain.

The cleanup form has one explanatory paragraph and the Include subdatasets,
Back up existing snapshots first and Confirm controls. Recursion is unchecked
on every fresh form, including links with a recursive query hint. Recursion and
backup-first are independent submitted options. The form defaults `backup_first`
to true; only an explicit zero opts out. A separate required confirmation checkbox is
unchecked by default.
The explanation states that re-enabling backups will require a full transfer.
Every submission requires administrator access, a POST and a scoped, single-use
CSRF token bound to the dataset. The existing CSRF/session lock prevents duplicate
submissions. The UI submits exactly one ordinary mutation with `recursive` and
`backup_first`. On API acceptance, it queues the standard in-progress notification
and redirects to the sanitized return page or dataset editor. The normal page
content and transaction sidebar remain available. Acceptance is not a claim that
cleanup has completed; the server continues its chain if the browser closes.

API rejections use the ordinary error perex and dataset editor. Transport and
response errors follow the existing error path without an acceptance notification,
a success redirect or an automatic retry. A failed task may have completed some
metadata edits or source deletions, so inspect its actual transactions and
remaining data before retrying. The UI has no cleanup-specific polling, result
screen or transaction-log block.

The API independently validates authorization and the locked scope. With
`backup_first` enabled, it requires complete existing or planned backup coverage
and verifies transfers before deleting source snapshots. The UI offers no force
option and never turns backup-first off automatically after an error.
Deploy the compatible API and scheduler together before exposing the action;
action discovery alone does not certify scheduler rollout. Storage guarantees,
partial failure and recovery are documented in [Disabling backups](storage/disable-backups.md).

Fast real-client and form regressions live in
`webui/tests/Regression/DatasetDisableBackupsTest.php`. The existing
`storage-backup-export` Playwright script covers administrator/member visibility,
routes, confirmation defaults and English/Czech rendering. Its confirmation
checks leave destructive shared fixtures intact; storage integration verifies
preservation and source cleanup against actual dataset contents.

## Removing all snapshot and backup history

The separate administrator action **Remove all snapshots and backup history**
appears below the backup-plan forms when the API advertises both
`Dataset.PreviewSnapshotRemoval` and `Dataset.RemoveSnapshots` with the complete
expected input/output contract. It works with no assigned plans or snapshots.
It preserves the live dataset and its files, while removing the reviewed source
and backup snapshots and relevant branches and trees. Unlike DisableBackups,
it does not preserve backup-pool history.

Include subdatasets starts unchecked. Remove selected datasets from backup
plans starts checked;
unchecking it retains schedules, which can recreate history after removal.
Preview is a read-only POST that returns a complete versioned inventory and
digest. The PHP client validates its required fields, references and counts
before rendering it. The page lists every source and backup snapshot location,
grouped by dataset and pool, plus all affected trees and branches (including
empty ones), plan memberships and remove/retain effects. It never derives the
deletion scope from a displayed snapshot page or silently truncates an inventory.

Two distinct confirmation stages follow preview. First, an initially unchecked
acknowledgement and Continue advance to a separate final confirmation form.
That form repeats the unchanged inventory, options and totals and requires a
fresh confirmation before submitting removal. Back to review returns to the
same inventory with the first acknowledgement unchecked. The PHP session owns
the validated inventory, options, digest and progression, bound to the dataset
and authenticated account/session context. Each stage uses a scoped one-use
CSRF token. A direct final POST, altered options/digest, account change, or replay
cannot bypass progression. The browser never supplies an authoritative delete set.

The final stage is consumed before its one removal call. Acceptance queues the
ordinary in-progress notification and redirects to the sanitized return page or
dataset editor; it does not claim deletion has finished. Known API rejection
uses the normal perex and requires a new preview and both confirmations. The
structured `errors.manifest_digest` marker `stale_preview` gives a localized
review-again message, clears the stale inventory and retains the selected
options. The API recomputes the inventory under its mutation locks before any
changes, so review-to-submit drift cannot silently delete unseen history.
Preview holds no storage locks between requests.

Transport failure or a missing task receipt never triggers automatic retry or
an acceptance notification. Inspect ordinary tasks and remaining history before
a deliberate new preview/retry; refreshing a preview alone does not establish
that an uncertain removal was rejected. Accepted tasks continue after the
browser closes. Removal can fail after deleting some history, so software
rollback cannot restore those snapshots; use ordinary task/transaction recovery
and review the remaining inventory before retrying. There is no new result page,
polling mechanism or force option.

Focused real-client, manifest, escaping and progression coverage lives in
`webui/tests/Regression/DatasetSnapshotRemovalTest.php`. The existing
`storage-backup-export` browser scenario covers bilingual defaults, preview,
review, final confirmation and Back without deleting its shared fixtures.
Actual history deletion and live-file preservation require isolated storage
integration coverage. Deploy compatible API support before exposing the UI;
client capability checks do not establish backend rollout readiness.
