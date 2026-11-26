# PHP WebUI backup cleanup

The dataset editor's Backup plans section exposes cleanup to administrators when
the API advertises `Dataset.DisableBackups`. It remains available with no plans.
VPS backups links to the same confirmation with the VPS root dataset and recursive
scope. Ordinary plan removal keeps its existing behavior and explains that
primary and backup snapshots remain.

The confirmation names the dataset and lists current descendants for a recursive
request. It defaults `backup_first` to true; only an explicit zero opts out.
Every submission requires administrator access, a POST and a scoped, single-use
CSRF token. The existing CSRF/session lock prevents duplicate submissions. The
UI submits exactly one mutation with `recursive` and `backup_first`, reads the
ordinary `_meta.action_state_id` receipt and polls for up to 15 seconds. It does
not read action-specific output or retain a separate session workflow.

Pending work links to the existing transaction task details. Those pages only
observe the accepted task. Closing the browser does not cancel accepted work;
the server continues its one chain. Completion is displayed only after known
successful receipt completion and fresh dataset/plan reads. A failed task may
have completed some metadata edits or source deletions, so inspect its actual
transactions and remaining data before retrying. Unknown submission or polling
outcomes link to the task or transaction log and never automatically resubmit.

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
