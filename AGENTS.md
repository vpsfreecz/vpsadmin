# Repository Guidelines

## Project Structure & Module Organization
- `api/`: Ruby 3.4 API with business logic, migrations in `db/migrate`, specs in `spec/`, plugins under `plugins/`.
- `webui/`: PHP front end (Composer-managed) plus light RSpec checks in `spec/`; config samples near `config_cfg.php`.
- `client/`, `nodectl*/`, `nodectld*/`, `libnodectld*/`: CLI tools and node daemons, each with its own `Gemfile`/`.rubocop.yml`.
- `nixos/`, `packages/`: NixOS modules and Nix package definitions for deployments.
- `doc/`: Architecture notes (`overview.mdwn`, `transactions.mdwn`) and operational docs.

## Build, Test, and Development Commands
- Enter a dev shell: `nix-shell` (root) or `nix-shell api/shell.nix` / `nix-shell webui/shell.nix` for component scopes.
- API: `cd api && bundle install && bundle exec rspec`; lint with `bundle exec rubocop`; local run via `bundle exec rackup -p 9292 config.ru`.
- Web UI: `composer install --working-dir=webui`; tests with `cd webui && bundle exec rspec`.
- Nix builds: `nix-build packages -A <attr>` or `nix-build nixos -A <module>` for module outputs.

## Coding Style & Naming Conventions
- Ruby: target Ruby 3.4, 2-space indent, snake_case. Run `bundle exec rubocop` in the touched component.
- PHP/JS in `webui`: mirror nearby code style; avoid sprawling scripts.
- Tests: name specs `*_spec.rb` with clear example names.
- Plugins: keep plugin gems inside the plugin directory; they are pulled via the `### vpsAdmin plugin marker ###` in `api/Gemfile`.

## Testing Guidelines
- No tests are currently in use, the existing test files are not known to be functional

## Commit & Pull Request Guidelines
- Use short imperative subjects, often scoped (`api: add StoragePool resource`, `webui: fix payset form`); keep one logical change per commit.
- PRs should state intent, note risky areas, list test commands run, and link issues; add screenshots/logs for UI/API behavior changes.

## Security & Configuration Tips
- Do not commit secrets; use samples in `api/config` and `webui/` plus local `.env` or Nix overlays.
- When changing Nix modules or deployment code, document option changes in the edited file and call out migrations in the PR.
