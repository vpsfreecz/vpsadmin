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
