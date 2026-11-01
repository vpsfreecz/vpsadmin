# Security advisories

Security advisories have an original report, structured node assessments and
separate update posts. Administrators can correct draft, published and retracted
reports. These corrections do not send mail, publish the advisory again, create
another advisory or add an update post. Use the separate
`security_advisory_updates` interface for an announcement; its mail option is
unchanged.

Only published advisories are visible to the public and signed-in members.
Draft and retracted advisories and their related records are visible only to
administrators. Retraction hides the advisory from non-admin readers while
preserving its content and history for administrators. It sends no email and
creates no update post.

## Correcting an original report

`PUT /security_advisories/:id` accepts the name and localized summary,
description, response and publication time in every state. Publication time can
be changed or cleared without changing the advisory state. A blank publication
time stays blank; list ordering then falls back to the creation time.

`PUT /security_advisories/:id/node_statuses/:row_id` corrects an existing node's
state, mitigation times and localized notes. Published and retracted rows require
`not_affected` or `mitigated`; mitigated rows require both `vulnerable_until` and
`mitigated_since`. Draft rows can also be `unknown` or `vulnerable`. Existing
active-node scope restrictions still apply. An unrelated node added after
publication does not prevent a correction. Omitted localized fields are
preserved; blank or null node notes clear that language's note. The existing
nested POST/DELETE actions add or remove node assessments. Removing a row is
also allowed after its node leaves the scope eligible for new assessments.

The existing `security_advisory_cves` create/update/delete actions correct CVE
links in every state, preserving normalized format and uniqueness. A CVE link
cannot move between advisories. Corrections can leave no CVE links or node
assessments; they do not run whole-advisory publication validation again.
Corrections preserve advisory identity, state, authorship and existing update
posts.

## Preconditions and atomicity

Original, CVE and node mutations, retraction and deletion require
`expected_content_revision`. A successful correction or retraction increments
`content_revision` once. Optional `expected_state` accepts `draft`, `published`
or `retracted` and requires the advisory to still have that state. State and
revision checks run under the parent advisory's database lock; a mismatch
returns HTTP 409 without changes. `expected_state` is a precondition, not a state
assignment. Only a draft can be published. Successful publication does not
increment the content revision.

Draft synchronization clients must send `expected_state: draft` on every original,
CVE and node mutation so a request prepared before publication cannot change a
published report. Before applying synchronization, check OPTIONS metadata for all
six actions used by sync: original Update, CVE Create/Delete and node
Create/Update/Delete. Support on the original and node PUTs alone is insufficient;
the client must refuse to apply sync against an older server before its first
write. Read-only planning remains available. Pause synchronization while upgrading
API servers and clients, update every active sync consumer, and avoid a mixed API
pool when checking this capability. Older clients may leave membership writes
unguarded even if they guard both PUTs.

Each request commits its fields, translations and any projection changes
together. A validation or rebuild failure rolls them all back, including the
revision and update time. The WebUI saves node rows as separate requests: an
error in a later row leaves earlier successful rows committed. Its forms submit
the rendered state and revision, preserving those values when an error is shown.

## Affected VPS and user snapshots

Published and retracted node creation, correction and deletion rebuild the
existing affected-VPS snapshot in the same transaction. The snapshot includes
current active or suspended VPSes on mitigated nodes, their current owner, environment, location and node, and the
corrected mitigation times. It does not reconstruct historical VPS placement.
Changing a node to `not_affected` removes its VPSes; changing it back to
`mitigated` adds current VPSes. Affected-user membership and VPS counts are
derived again. The affected-node count includes mitigated rows.

Manual rebuilds use the same parent lock as corrections and publication, with
fresh reads of node rows, VPSes and projections. Original text edits,
draft node edits and CVE corrections do not rebuild the snapshot. Rebuilds and
corrections never send mail.

## Retraction and deletion

`POST /security_advisories/:id/retract` is an admin-only silent action with scope
`security_advisory#retract`. It accepts the ordinary `security_advisory` wrapper
with revision/state preconditions. It requires a published advisory, sets its
state to `retracted`, records the retraction time and increments the revision
once. Publication time/authorship, update posts and affected projections remain.
It creates no update post and sends no mail. A stale retry conflicts; a fresh
request to retract an already retracted advisory is an invalid transition.

`DELETE /security_advisories/:id` is admin-only with scope
`security_advisory#delete`. Its JSON body uses the same wrapper and preconditions.
It permanently deletes the original report, update posts and their translations,
CVE links, node assessments/notes, affected projections and outage links.
Referenced users, nodes, VPSes, environments, locations and outages remain, as do
transaction concerns and mail/log history. Repeating a successful delete returns
404. Deletion is transactional: a dependent failure restores the entire report.
Recovery requires an existing backup; software rollback cannot restore it.

Existing scoped tokens do not gain retract/delete permissions automatically.
The separate update-post interface retains its explicit state/publication-time
changes and optional mail choice. Parent locks serialize its writes and outage
link creation with correction and deletion, preventing orphan child records.

No schema conversion is needed to read corrected content with older software.
Rolling the API back restores its previous editing restrictions and makes an
updated sync client refuse to apply changes. Corrected data remains in place;
software rollback does not reverse a correction.
