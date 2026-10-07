# Testing and CI

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

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
- CI (GitHub Actions) runs API specs in the static topics described below.
  When adding, renaming or moving a spec, update the explicit topic patterns in
  `.github/workflows/api-specs.yml` so every eligible file belongs to exactly one
  topic in both plugin modes.

## API spec topics

`.github/workflows/api-specs.yml` defines thirteen static topics, shared by the
full (`VPSADMIN_PLUGINS=all`) and core (`VPSADMIN_PLUGINS=none`) matrices. Each
job runs one RSpec process with its own temporary MariaDB database and normal
randomized order. Keep the example filters and plugin-dependent pending behavior
when changing the partition. Migration specs have a separate workflow; the
eligible files are the tracked `spec/**/*_spec.rb` paths under `api/`, excluding
`spec/migrations/*_spec.rb`. The generator file remains selected, while RSpec
excludes `:generator` examples unless `RUN_GENERATOR_SPECS=1`.

Paths in the table are relative to `api/`. Resource entries mean
`spec/api/resources/<entry>_spec.rb`, including any glob shown. The workflow's
patterns are authoritative; place new specs in the matching domain and extend
its explicit patterns if needed.

| Topic | Files or resource entries |
| --- | --- |
| `foundation` | `spec/smoke/**/*_spec.rb`, `spec/api/custom_routes_coverage_spec.rb`, `spec/api/endpoint_coverage_spec.rb`, `spec/api/generate_pending_endpoints_spec.rb`, `spec/api/routes/**/*_spec.rb`, `spec/models/**/*_spec.rb`, `spec/supervisor/**/*_spec.rb` |
| `plugins` | `spec/api/plugins/**/*_spec.rb` |
| `dns` | `dns*` |
| `storage` | `dataset_*`, `environment_dataset_*`, `pool_*`, `snapshot_download`, `export`, `storage_freeze` |
| `mail` | `mail*`, `mailbox`, `user_mail_*` |
| `vps` | `vps_*` |
| `platform-infrastructure` | `node_*`, `os_*`, `migration_plan` |
| `platform-operations` | `security_advisory*`, `oom_report*`, `incident_report`, `lifecycle_bypass`, `object_history`, `transaction*` |
| `platform-config` | `spec/lib/**/*_spec.rb`, `action_state`, `api_server`, `cluster*`, `component`, `debug`, `default_object_cluster_resource`, `environment_read`, `environment_write`, `language`, `location_read`, `location_write`, `metrics_access_token`, `system_config` |
| `auth` | `oauth2_client`, `password_change_log`, `webauthn`, `user_known_device`, `user_public_key`, `user_session`, `user_totp_device`, `user_webauthn_credential` |
| `users` | `user_cluster_resource*`, `user_environment_config`, `user_namespace*`, `user_read`, `user_state_log`, `user_touch`, `user_available_ips`, `user_write` |
| `ip-ownership` | `ip_address*`, `ip_release*` |
| `network` | `network_*`, `network_interface*`, `host_ip_address`, `location_network` |

The selector expands each topic's patterns and sorts/deduplicates its manifest.
Overlap inside a topic, such as the mail or network globs, is allowed. Overlap
between topics fails coverage. Keep every topic nonempty, avoid catch-all
patterns, and update the anchored matrix and the aggregate's `EXPECTED_TOPICS`
list together when renaming topics.

The stable check `API specs - topic coverage` requires both matrices to succeed
and validates each mode separately against the eligible tracked files. It
requires exactly the configured thirteen nonempty manifests per mode, rejects
missing/duplicate/untracked paths and unexpected artifact contents, and requires
full/core membership to agree for every topic. A failed, cancelled or incomplete
matrix cannot pass the aggregate using manifests uploaded before testing.

Each job uploads these artifacts for seven days, including on failure:

- `rspec-files-<mode>-<topic>` contains `rspec-files-<mode>-<topic>.txt`, selected
  before dependency setup, with paths relative to `api/`.
- `rspec-results-<mode>-<topic>` contains native RSpec
  `rspec-results-<mode>-<topic>.json`,
  `rspec-environment-<mode>-<topic>.json` and the exact effective
  `rspec-Gemfile-<mode>-<topic>.lock`. RSpec also prints the documentation formatter
  to stdout and retains its failure exit status. Environment evidence records
  the mode/topic, Ruby/RubyGems/Bundler/RSpec versions, sorted resolved gem
  name/version/platform values and SHA256 of that lock companion. CI uses the
  generated `api/Gemfile.lock`, not `packages/api/Gemfile.lock`. Resolved specs
  describe the effective bundle; they do not prove that every gem was loaded.

Missing or malformed result JSON is incomplete evidence. For comparisons, use
artifacts from explicit run IDs and attempts, retain their separate directories,
and compare full/core independently. Require matching example IDs, statuses and
pending reasons across partitions, plus consistent effective dependency evidence.
Normalize only a harmless leading `./` in paths/IDs; keep the full scoped ID
suffix. Seed, order and duration may differ. A selected file can have no executed
examples after filtering, so manifest coverage and example parity are separate
checks.

### Request exception evidence

The spec Rack app observes HaveAPI exception dispatch before a listener can stop
it. On failure, an example emits one `API_REQUEST_EXCEPTION_DIAGNOSTICS ` reporter
message containing diagnostic format 1 JSON. The native JSON formatter retains
the message in `messages`. Passing and pending examples discard their buffers.
For each request, the wrapper calls the original memoized app once and preserves
its status, headers and body.

Each event is bound to the current example, request ordinal, execution thread and
exact in-flight Rack environment. It records the method, final HTTP status when
available, dispatcher name, primary exception class and up to two cause classes.
Frames contain only enumerated public Ruby source IDs and line numbers from the
checkout API/plugin source or loaded gem `lib` files. It records no exception
message, SQL, request path, parameters, headers, body, credentials or absolute
paths. This restriction applies to the new packet; it does not sanitize existing
framework or RSpec output.

Each example retains at most eight events and 16 KiB, including the fixed prefix.
The observer inspects at most 64 locations per exception and retains at most six
public frames. Cycles and truncation have fixed indicators. Unknown values and
observer errors use fixed markers. Nested calls restore their scope, and calls outside
the current request are not attributed to an earlier request. Both dispatcher
stages remain distinct. Earlier request events stay grouped with their actual
example; they are not assigned to its final failing assertion. Missing
output after process loss or an outside-example error is incomplete evidence.

`spec/ci_environment.rb` uses Bundler's effective lockfile and resolved specs.
The helper copies exact lock bytes only after validating regular files within
its size bounds, fresh ordinary outputs and public rubygems.org-only sources.
It refuses credential-bearing, GIT, PATH and unknown source forms without
excerpts. The results artifact allowlist contains only its three explicit
companions. Missing lock/environment
companions leave dependency reproduction unproved; a preparation failure is
separate from an RSpec failure.

For focused diagnostics, enter the declared API shell separately for each mode
and run:

```bash
VPSADMIN_PLUGINS=none nix develop .#api -c bundle exec rspec spec/smoke/request_exception_diagnostics_spec.rb spec/smoke/api_boot_spec.rb spec/api/resources/environment_write_spec.rb --format documentation --format json --out "$DIAGNOSTIC_RESULT"
VPSADMIN_PLUGINS=all nix develop .#api -c bundle exec rspec spec/smoke/request_exception_diagnostics_spec.rb spec/smoke/api_boot_spec.rb spec/api/resources/environment_write_spec.rb --format documentation --format json --out "$DIAGNOSTIC_RESULT"
```

Use separate fresh result destinations and the ordinary owned disposable database
contract. Keep the exact source, mode, example IDs, seed, order and dependency
companions when diagnosing CI. A local pass with a different Ruby, Bundler or
lock does not explain a prior generic HTTP 500. These diagnostics provide test
evidence only; API behavior, production handlers, authorization and database
contracts are unchanged.
Old checkouts and rollback lack the new evidence without changing API behavior.

### Local topic reproduction

From the repository root, enter `VPSADMIN_PLUGINS=all nix develop .#api` for full
mode. Use `VPSADMIN_PLUGINS=none nix develop .#api` for core and set `mode=core`
below. The shell starts in `api/`. This selects patterns from the actual matrix
and runs the same two formatters; adjust `topic` to one of the table's names.

```bash
set -euo pipefail
shopt -s nullglob globstar
topic=platform-infrastructure
mode=full
patterns="$(bundle exec ruby -ryaml -e '
  workflow = YAML.load_file("../.github/workflows/api-specs.yml", aliases: true)
  topics = workflow.fetch("jobs").fetch("api-specs-full").fetch("strategy").fetch("matrix").fetch("include")
  topic = topics.find { |entry| entry.fetch("topic") == ARGV.fetch(0) }
  abort "Unknown topic" unless topic
  puts topic.fetch("patterns")
' "$topic")"
files=()
while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  for file in $pattern; do
    files+=("$file")
  done
done <<< "$patterns"
(( ${#files[@]} > 0 )) || { echo "Empty topic" >&2; exit 2; }
mkdir -p tmp
manifest="tmp/rspec-files-$mode-$topic.txt"
printf '%s\n' "${files[@]}" | sort -u > "$manifest"
mapfile -t files < "$manifest"
bundle exec rspec "${files[@]}" --format documentation --format json \
  --out "tmp/rspec-results-$mode-$topic.json"
```

For a partition change, expand both the old and new patterns and compare the
complete eligible file sets in each mode. Validate the actual aggregate step
with missing, empty, duplicate, extra, wrong-topic/mode and incomplete manifests,
and unsuccessful matrix results. Check readable output, parseable native JSON
and the nonzero exit status on an example failure. Run the declared hooks and
workflow/shell lint before committing.
