# Repository Guidelines


## Required procedures

Before each activity below, read every applicable procedure in full. These are
required instructions with repository scope, including outside this workspace.
Resolve table links from this AGENTS.md, not the shell directory. Recheck routes
when scope changes; pass applicable paths to authorized subagents before they
act. Reuse unchanged procedures already read in the current context; otherwise
reread them. Summaries do not replace reading. If a required file is unreadable,
stop the affected action and report it.

| Before this activity | Read |
| --- | --- |
| Selecting/running builds, tests, component shells, dependency setup or manual test-database operations | [Development commands](docs/agent-instructions/development.md) |
| Changing visible WebUI behavior (including labels, navigation or screenshots), translations, localization behavior or member-facing mail templates | [Localization and KB impact](docs/agent-instructions/localization.md) |
| Selecting/running tests or CI on existing changes; planning/implementing a change that needs verification; adding/moving runtime files or API specs; changing integration/Playwright tests, CI selection, gem packaging or VPS data-preservation operations | [Testing and CI](docs/agent-instructions/testing.md) |

Visible WebUI changes require the external KB documentation workflow even if
vpsAdmin tests pass; read the localization procedure before proceeding. Tests
of the data-preserving VPS operations listed in the testing procedure must
verify that data survives. Preserve CI runtime test selection and exact-once API
spec topic coverage when files move or change.
Do not create build IDs or upload first-party gems to a remote RubyGems repository.


## Project Structure & Module Organization
- `api/`: Ruby 3.4 API with business logic, migrations in `db/migrate`, specs in `spec/`, plugins under `plugins/`.
- `webui/`: PHP front end (Composer-managed); config samples near `config_cfg.php`.
- `client/`, `nodectl*/`, `nodectld*/`, `libnodectld*/`: CLI tools and node daemons, each with its own `Gemfile`/`.rubocop.yml`.
- `nixos/`, `packages/`: NixOS modules and Nix package definitions for deployments.
- `docs/`: Markdown documentation for developers and operators. Start with
  [docs/README.md](docs/README.md); update the relevant pages with code changes
  and follow the writing conventions in that index.

## Relationship With vpsAdminOS
- vpsAdmin commonly drives vpsAdminOS feature needs, but vpsAdminOS remains an
  independent general-purpose container host platform.
- When a vpsAdmin feature needs vpsAdminOS changes, keep vpsAdmin-specific
  policy, database semantics, backup ownership, and orchestration in vpsAdmin
  or nodectld/libnodectld integration code where possible.
- Shape osctld/osctl-facing requests as reusable primitives that make sense for
  non-vpsAdmin users. If a vpsAdmin-specific contract is unavoidable, document
  the boundary and compatibility expectations in the change.

## Coding Style & Naming Conventions
- Ruby: target Ruby 3.4, 2-space indent, snake_case. Run `bundle exec rubocop` in the touched component.
- PHP/JS in `webui`: mirror nearby code style; avoid sprawling scripts.
- Tests: name specs `*_spec.rb` with clear example names.
- Plugins: keep plugin gems inside the plugin directory; they are pulled via the `### vpsAdmin plugin marker ###` in `api/Gemfile`.
- Database schema: `api/db/schema.rb` is for core vpsAdmin tables only. Dump it
  from a core-only environment, e.g. with `VPSADMIN_PLUGINS=none`; plugin
  tables belong in `plugins/*/api/db/migrate` and must not be committed to the
  core schema file.

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
