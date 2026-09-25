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
  `rspec-results-<mode>-<topic>.json` and
  `rspec-environment-<mode>-<topic>.json`. RSpec also prints the documentation
  formatter to stdout and retains its failure exit status. Environment evidence
  records the mode/topic, Ruby/Bundler/RSpec versions and SHA256 of the effective
  generated `api/Gemfile.lock`; CI does not resolve from `packages/api/Gemfile.lock`.

Missing or malformed result JSON is incomplete evidence. For comparisons, use
artifacts from explicit run IDs and attempts, retain their separate directories,
and compare full/core independently. Require matching example IDs, statuses and
pending reasons across partitions, plus consistent effective dependency evidence.
Normalize only a harmless leading `./` in paths/IDs; keep the full scoped ID
suffix. Seed, order and duration may differ. A selected file can have no executed
examples after filtering, so manifest coverage and example parity are separate
checks.

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
