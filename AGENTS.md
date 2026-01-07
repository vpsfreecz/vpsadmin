# Repository Guidelines
This is a monorepo. Each component has its own `Gemfile`/`gemspec`/`composer.lock`/`go.mod`/lock file.

## Project Structure & Module Organization
- `api/`: Ruby 3.4 API with business logic, migrations in `db/migrate`, specs in `spec/`, plugins under `plugins/`. The API also contains the `supervisor` in `api/lib/vpsadmin/supervisor/`, which is processing rabbitmq messages from `nodectld`.
- `client/`: CLI tool for working with the API, used by external clients.
- `nodectld/`: Ruby daemon running on all nodes, processing commands from the API and communicating with the `supervisor`. `nodectld` uses `vpsAdminOS` to run VPS as Linux containers.
- `nodectl/`: CLI for `nodectld`.
- `libnodectld/`: Ruby library, most of the code for `nodectld` is here.
- `console_router/`: Ruby web application that is proxying remote VPS console connections between external clients and `nodectld`. Clients connect using HTTP, rabbitmq messages are used for communication with `n
- `webui/`: PHP front end (Composer-managed) for the API; config samples near `config_cfg.php`.
- `nixos/`: NixOS modules for deployment of all of vpsAdmin's services.
- `packages/`: Nix package definitions.
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
- Integration tests live in `tests/` and reuse the vpsAdminOS test framework; `vpsadminos` is usually available at `../vpsadminos`. If not, you can clone it next to this repo (or set `VPSADMINOS_PATH`) so the runner can add it to `NIX_PATH`.
- Use `./test-runner.sh ls` to enumerate tests and `./test-runner.sh test <test>` (e.g. `vpsadmin/services-up`).
- Test definitions are in `tests/all-tests.nix` and `tests/suite/*`; machines compose `tests/machines/v4/cluster/*.nix` plus seeds from `api/db/seeds/test*.nix` to spin up services and vpsAdminOS nodes on user+socket networks.
- Services VM config `tests/configs/nixos/vpsadmin-services.nix` seeds MariaDB/RabbitMQ/Redis credentials from `tests/configs/nixos/vpsadmin-credentials.nix`, enables API/webui/supervisor/console_router; adjust socket addresses via `vpsadmin.test.*`.
- Scenarios include cluster smoke tests, node registration, VPS create/start, and VPS migrate between nodes; expect long-running Nix builds/VM boots rather than quick unit specs.
- test-runner extension `tests/runner/extensions/vpsadmin_services.rb` adds a `vpsadminctl` helper and `wait_for_vpsadmin_api` for machines tagged `vpsadmin-services`.

## Commit & Pull Request Guidelines
- Use short imperative subjects, often scoped (`api: add StoragePool resource`, `webui: fix payset form`); keep one logical change per commit.
- PRs should state intent, note risky areas, list test commands run, and link issues; add screenshots/logs for UI/API behavior changes.

## Security & Configuration Tips
- Do not commit secrets; use samples in `api/config` and `webui/` plus local `.env` or Nix overlays.
- When changing Nix modules or deployment code, document option changes in the edited file and call out migrations in the PR.
