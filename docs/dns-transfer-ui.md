# DNS transfer evidence in the PHP WebUI

The external-zone detail separates the secondary's local serving observation
from its ability to transfer from each user-configured primary. A loaded serial
or a successful peer transfer does not establish direct primary readiness.
The transfer log retains the source kind and historical attempts separately.

The primary summary uses the API's readiness aggregate and counts. Failed and
pending summaries include path details from `DnsServerZonePrimaryTransferState`.
Only `evidence_current: true` can display a path as currently successful or
failed. A stale result stays available as previous evidence, with its source,
observation, last-success and reason times. Missing paths and raw unknown states
remain pending. The WebUI does not derive freshness from `last_attempt_at`.

The missing-primary diagnostic queries existing `primary_type` associations
independently of the displayed page. Peers and probe rows cannot satisfy it.
An owned detached primary still counts as configured.

Attachment comes from included transfer → host → allocation → network interface
and owner data. The WebUI inspects the included attributes directly to avoid
implicit host lookups, which cannot resolve detached hosts for ordinary members.
An explicit null parent interface plus matching allocation and zone ownership
produces the detached warning. Missing expansion remains unknown. Host order and
the host's assigned flag do not describe attachment of its routed allocation.

An API without the readiness resource and currentness output keeps ordinary DNS
controls and historical last-attempt information; readiness is unavailable. The
WebUI never interprets the last recorded attempt as current readiness. Existing
authorization still controls all API requests and association expansions.

Semantic documentation IDs accompany zone creation, primary addition, TSIG
selection and TSIG creation. The external
[`vpsfree-kb-contracts` workflow](https://github.com/vpsfreecz/vpsfree-kb-contracts/blob/master/docs/webui-change-workflow.md)
binds these controls to bilingual instructions and immutable application inputs.
Changing the display does not publish KB content.
