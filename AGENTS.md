# Repository Guidelines

## Project Structure & Module Organization
- `api/`: Ruby 3.4 API with business logic, migrations in `db/migrate`, specs in `spec/`, plugins under `plugins/`.
- `webui/`: PHP front end (Composer-managed); config samples near `config_cfg.php`.
- `client/`, `nodectl*/`, `nodectld*/`, `libnodectld*/`: CLI tools and node daemons, each with its own `Gemfile`/`.rubocop.yml`.
- `nixos/`, `packages/`: NixOS modules and Nix package definitions for deployments.
- `doc/`: Architecture notes (`overview.mdwn`, `transactions.mdwn`) and operational docs.

## Relationship With vpsAdminOS
- vpsAdmin commonly drives vpsAdminOS feature needs, but vpsAdminOS remains an
  independent general-purpose container host platform.
- When a vpsAdmin feature needs vpsAdminOS changes, keep vpsAdmin-specific
  policy, database semantics, backup ownership, and orchestration in vpsAdmin
  or nodectld/libnodectld integration code where possible.
- Shape osctld/osctl-facing requests as reusable primitives that make sense for
  non-vpsAdmin users. If a vpsAdmin-specific contract is unavoidable, document
  the boundary and compatibility expectations in the change.

## Build, Test, and Development Commands
- Enter a dev shell with flakes: `nix develop` (or `nix develop .#vpsadmin`) for root actions, and `nix develop .#api` / `nix develop .#webui` / `nix develop .#client` / `nix develop .#console-router` / `nix develop .#nodectl` / `nix develop .#nodectld` / `nix develop .#libnodectld` for component scopes.
- API: `cd api && bundle install && bundle exec rspec`; lint with `bundle exec rubocop`; local run via `bundle exec rackup -p 9292 config.ru`.
- API and libnodectld RSpec suites need MariaDB. In local Nix dev shells,
  `bundle exec rspec` starts an isolated temporary test database automatically
  when neither `DATABASE_URL` nor `api/config/database.yml` is configured. Use
  `VPSADMIN_TEST_DB_AUTO=0` to disable automatic startup.
- For manual database debugging from `api/` or `libnodectld/`, use
  `../tools/test-db start`, `eval "$(../tools/test-db env)"`,
  `../tools/test-db status`, `../tools/test-db client`,
  `../tools/test-db stop`, and `../tools/test-db prune`. The default URL is
  `mysql2://root:root@127.0.0.1:13306/vpsadmin_test`; libnodectld specs append
  `_libnodectld` through their shared DB setup.
- Web UI: `composer install --working-dir=webui`; browser integration tests run with `./test-runner.sh test webui`.
- Nix builds: `nix-build packages -A <attr>` or `nix-build nixos -A <module>` for module outputs.

## Coding Style & Naming Conventions
- Ruby: target Ruby 3.4, 2-space indent, snake_case. Run `bundle exec rubocop` in the touched component.
- PHP/JS in `webui`: mirror nearby code style; avoid sprawling scripts.
- Tests: name specs `*_spec.rb` with clear example names.
- Plugins: keep plugin gems inside the plugin directory; they are pulled via the `### vpsAdmin plugin marker ###` in `api/Gemfile`.
- Database schema: `api/db/schema.rb` is for core vpsAdmin tables only. Dump it
  from a core-only environment, e.g. with `VPSADMIN_PLUGINS=none`; plugin
  tables belong in `plugins/*/api/db/migrate` and must not be committed to the
  core schema file.

## Localization

### Knowledge-base documentation impact

Any feature that changes something visible in the WebUI may affect localized
KB navigation text or screenshots. Follow the canonical workflow in
`vpsadmin-kb-captures/docs/webui-change-workflow.md`: pin the vpsAdmin feature
commit there, run its documentation contract, and review every reported Czech
and English page and screenshot concept. A green vpsAdmin test suite alone does
not prove that external documentation remains current.

- Czech translation guidelines are documented in `doc/i18n-cs.md`. Follow the
  terminology there when editing API or WebUI Czech translations.
- API translations are maintained in `api/lib/vpsadmin/api/locales/*.yml` and
  normalized by `rake vpsadmin:i18n:update`.
- vpsAdmin sets HaveAPI `parameter_i18n_scope` to the `vpsadmin` application
  root. Parameter labels/descriptions are generated under
  `vpsadmin.resources`, `vpsadmin.attributes`, and `vpsadmin.meta`; do not add a
  separate `vpsadmin.parameters` tree.
- Every new or changed API parameter must have a human-friendly label. It must
  also have a description that explains its meaning or purpose unless the
  meaning is already obvious and a description would add no useful
  information. Identifier-derived labels such as `Expires_at` do not satisfy
  this requirement.
- The locale files include generated key structure from API source and HaveAPI
  parameter metadata. Edit translations in the locale files, then regenerate.
- WebUI runtime translations use gettext domain `vpsAdmin`. Source strings are
  `_()` calls in PHP; the generated source catalog is
  `webui/lang/locale/vpsAdmin.pot`.
- WebUI translations are edited in
  `webui/lang/locale/<locale>/LC_MESSAGES/vpsAdmin.po`; compiled
  `vpsAdmin.mo` files are generated artifacts. Locale maintenance scripts live
  in `webui/lang/scripts/`.
- WebUI language selection uses the browser language for guests, then the
  logged-in user's `User.language` preference. The top-right language switcher
  updates that preference for normal sessions and remains session-only while an
  admin is impersonating another user.

## Testing Guidelines
- Integration tests live in `tests/` and reuse the vpsAdminOS test framework via the flake input, so no sibling `vpsadminos` checkout or `NIX_PATH` setup is required.
- For local gem development of `libnodectld`, `nodectl`, or `nodectld` against a checkout, set `VPSADMINOS_PATH=/path/to/vpsadminos`.
- Run `rake vpsadmin:gems` to refresh all packaged Ruby gem metadata. Use
  `rake -T vpsadmin:gems` to list individual package tasks when only one
  package has to be refreshed. Do not create build IDs or upload first-party
  gems to a remote RubyGems repository.
- Use `./test-runner.sh ls` to enumerate tests and `./test-runner.sh test <test>` (e.g. `services-up`).
- Test definitions are in `tests/all-tests.nix` and `tests/suite/*`; machines compose `tests/machines/cluster/*.nix` plus seeds from `api/db/seeds/test*.nix` to spin up services and vpsAdminOS nodes on user+socket networks.
- Tests that transfer, migrate, reinstall, replace, back up, or restore a VPS
  dataset must verify data integrity when the operation is expected to preserve
  data. Create a file at a known path with known contents, or an equivalent
  payload checksum, before the operation and assert that it survives intact on
  the destination or restored dataset.
- Services VM config `tests/configs/nixos/vpsadmin-services.nix` seeds MariaDB/RabbitMQ/Redis credentials from `tests/configs/nixos/vpsadmin-credentials.nix`, enables API/webui/supervisor/console_router; adjust socket addresses via `vpsadmin.test.*`.
- Scenarios include cluster smoke tests, node registration, VPS create/start, and VPS migrate between nodes; expect long-running Nix builds/VM boots rather than quick unit specs.
- test-runner extension `tests/runner/extensions/vpsadmin_services.rb` adds a `vpsadminctl` helper and `wait_for_vpsadmin_api` for machines tagged `vpsadmin-services`.
- Changes under `webui/` that affect user-visible behaviour should be covered
  by relevant Playwright browser tests when practical. Run all webui scripts
  with `./test-runner.sh test 'webui#*'`. List current scripts with
  `./test-runner.sh ls 'webui#*'`, then target one with
  `./test-runner.sh test 'webui#<script-name>'`.
- CI (GitHub Actions) runs push integration tests selectively using
  `.github/workflows/ci.yml`, `tools/select_ci_tests.rb`,
  `tests/ci-selection.yml`, and derived metadata tags from `tests/ci-tags.nix`.
  When adding, renaming, or moving runtime files, integration tests, or webui
  Playwright scripts, update the selection rules/tags in the same change so
  affected pushes continue to run the right `tag=ci && (...)` filter. Unknown
  runtime paths intentionally fall back to the full `tag=ci` suite; prefer
  broader tags over under-selecting tests. Validate selector changes with
  `ruby tests/ci-selection-test.rb` and representative
  `./test-runner.sh ls --filter 'tag=ci && (...)'` commands.
- CI (GitHub Actions) runs `api/spec/**` in parallel **topic jobs** defined in `.github/workflows/api-specs.yml`.
  When adding/renaming/moving API spec files, you **must** update the workflow's topic patterns so every spec is covered
  exactly once. The CI job "API specs - topic coverage" will fail if any spec is missing or matches multiple topics.

## Event Coverage

- Read `doc/events.mdwn` before adding or changing an API mutation, operation,
  authentication flow, callback, bulk write, or transaction chain.
- Every mutating HaveAPI action and non-action mutation entry point must have
  an `event_policy` declaration or a validated standard-action inference.
  Declare all models changed by custom code beside that action or operation;
  policies for read-only, bookkeeping, transport, or semantic event paths must
  include a concrete reason.
- Keep policy kinds and their valid option combinations closed and validated.
  External boundaries must derive their wrappers and policy names from one
  owner declaration instead of repeating method-to-policy mappings.
- Resource events are typed `<logical_resource>.created`, `.updated`, and
  `.deleted` events. Do not add generic `resource.*` event types, and do not
  reuse these reserved names for a notification/workflow payload with a
  different source or contract.
- The Event API and WebUI are notification delivery history, not an audit log.
  Public events are retained only when routing produces delivery work; absence
  from the Event index is not evidence that a mutation did not happen.
- Consumers that require a complete external audit stream must configure an
  explicit catch-all route to a durable receiver and retain delivered events
  themselves. Do not use unconditional Event persistence to bypass routing.
- Add generated CRUD types only with `resource_events` beside a mounted
  model-backed HaveAPI resource. Declare its logical name when needed, stable
  topic, `account` or `admin` audience, and ownership/context policy. Mounted
  default CRUD actions are inferred; reserve `additional_actions` for emitted
  outcomes outside those defaults. Plugin resources keep declarations in their
  owning plugin.
- Do not declare internal storage-placement/clone rows, authentication
  implementation rows, translations, joins, delivery internals, accounting,
  telemetry, or read-only projections. Callbacks for undeclared resources are
  intentionally ignored; direct undeclared resource emission is an error.
- Account resource declarations require an explicit owner resolver and publish
  roles `account, admin`; admin declarations publish role `admin`. Event Type
  API tests must cover ordinary/support/admin visibility and matching filtered
  counts.
- Describe and match logical emitted values, not database storage values:
  enums use their symbolic strings and serialized YAML/JSON attributes use
  `json`. Decimals are emitted as lossless strings. Composite primary keys are
  keyed objects and do not expose a scalar `resource_id` route matcher.
- Emit synchronous resource facts only after a successful mutation. Chain
  builders must defer past-tense resource/domain facts until `done`; a failed
  chain emits `operation.failed` and no false completion facts.
- Correlate chain lifecycle and completion facts with `operation_id`. Do not
  expose execution-attempt counters as part of the public event contract.
- Keep logical-name, owner/VPS, and public redaction policy in the resource's
  `resource_events` declaration. Declare callback-bypassing cascades and
  internal redaction beside the owning model with `event_delete_cascades` and
  `event_redact`. An internal transaction concern with no public resource must
  declare its account path with `operation_event_owner`; do not add it to a
  central class-name resolver. Validate redacted fields against the owning
  model's auditable attributes during catalog finalization. Never expose
  secrets, tokens, private/key
  material, opaque configuration, notification-template bodies, delivery
  payloads, or VPS user-data content in event changes.
- Use explicit recorder helpers for bulk SQL writes that skip Active Record
  callbacks. Represent internal translation/join rows through the logical
  public parent where practical.
- Update resource event specs and Event Type metadata expectations. Keep the
  action/operation/external-boundary coverage checks strict.

## Notification Delivery Architecture

- Implement each notification delivery method as a registered subclass of
  `Notifications::DeliveryActions::Base` in its own file. Keep its action and
  target metadata, configuration defaults, planning, validation, preparation,
  transport, and response handling on that implementation.
- Keep routing and dispatch protocol-neutral. Pass explicit context objects to
  delivery actions; do not depend on `instance_exec`, `send`, or callback
  rebinding to make one component execute in another component's scope.
- Delivery implementations must return a validated `DeliveryResult` with a
  supported outcome or raise `DeliveryFailure`. Keep provider-specific failure
  classes behind that generic boundary so the dispatcher does not branch on
  transport protocols or interpret arbitrary return values as success.
- Reject duplicate action names, queues, routing keys, and conflicting target
  labels during registration. Cover a new action by extending registry and
  interface contract specs, not by adding mirrored action-name branches to
  routers, models, and workers.
- Keep deployable action names open to registered implementations. When Nix
  must duplicate evaluation-time defaults, emit a deployment contract and
  validate it against the Ruby registry at process startup; cover both default
  drift and a new syntactically valid action in tests.

## Commit & Pull Request Guidelines
- Use short imperative subjects, often scoped (`api: add StoragePool resource`, `webui: fix payset form`); keep one logical change per commit.
- Every commit message must explain what the change does and why it is
  needed; use the subject for the action and the body for the rationale
  when needed.
- Wrap every commit message line at 80 characters or fewer.
- Always write the commit message to a temporary file and commit with
  `git commit -F <tmpfile>` instead of passing the message inline.
- Flake input updates (`vpsadminos`) must be done with
  `tools/update_vpsadminos_flake.sh`. The script reads the current and new
  revs, updates only the `vpsadminos` input, verifies that only `flake.lock`
  changed, and commits with subject format
  `flake: vpsadminos <old9> -> <new9>`.
- PRs should state intent, note risky areas, list test commands run, and link issues; add screenshots/logs for UI/API behavior changes.

## Security & Configuration Tips
- Do not commit secrets; use samples in `api/config` and `webui/` plus local `.env` or Nix overlays.
- When changing Nix modules or deployment code, document option changes in the edited file and call out migrations in the PR.
