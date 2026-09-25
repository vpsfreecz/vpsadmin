#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd "$(dirname "$0")/../../.." && pwd -P)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/storage-group-cleanup.XXXXXXXX")"
trap 'rm -rf -- "$fixture_dir"' EXIT
mkdir "$fixture_dir/bin"

# The fake Nix command never starts MariaDB or runs RSpec. The real URL helper
# still creates a disposable URL, which run.sh must keep out of its output.
cat >"$fixture_dir/bin/nix" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *'tools/test-db stop'*) exit "${CONTRACT_FAKE_STOP_STATUS:-23}" ;;
  *'api_producer_spec.rb'*) exit "${CONTRACT_FAKE_PRODUCER_STATUS:-0}" ;;
esac
exit 0
SH

# Avoid a real TCP bind while choosing a port. All other Ruby calls, including
# the private URL validation, use the ordinary interpreter.
cat >"$fixture_dir/bin/ruby" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == '-rsocket' && "${2:-}" == '-e' && "${3:-}" == *'TCPServer.new'* ]]; then
  printf '22345'
  exit 0
fi
if [[ "${1:-}" == '-rsocket' && "${2:-}" == '-e' && "${3:-}" == *'Socket.tcp'* ]]; then
  exit "${CONTRACT_FAKE_PROBE_STATUS:-0}"
fi
exec "$CONTRACT_TEST_REAL_RUBY" "$@"
SH
chmod 755 "$fixture_dir/bin/nix" "$fixture_dir/bin/ruby"

check_case() {
  expected_status="$1"
  producer_status="$2"
  stop_status="$3"
  probe_status="$4"
  failed_stage="$5"
  case_dir="$fixture_dir/case-$expected_status"
  mkdir "$case_dir"

  set +e
  output="$(env TMPDIR="$case_dir" PATH="$fixture_dir/bin:$PATH" \
    CONTRACT_TEST_REAL_RUBY="$(command -v ruby)" \
    CONTRACT_FAKE_PRODUCER_STATUS="$producer_status" \
    CONTRACT_FAKE_STOP_STATUS="$stop_status" \
    CONTRACT_FAKE_PROBE_STATUS="$probe_status" \
    "$repo_root/tests/contracts/storage_group_snapshot_v4/run.sh" 2>&1)"
  actual_status=$?
  set -e

  [[ "$actual_status" == "$expected_status" ]] || {
    printf 'unexpected cleanup exit: %s, expected %s\n' "$actual_status" "$expected_status" >&2
    exit 1
  }
  [[ "$output" == *"failed at $failed_stage (exit $stop_status)"* ||
     "$output" == *"failed at $failed_stage (exit $probe_status)"* ]]
  [[ "$output" != *'contract passed'* ]]
  [[ "$output" != *'mysql2://'* ]]

  shopt -s nullglob
  retained=("$case_dir"/storage-group-v4.*)
  [[ "${#retained[@]}" == 1 && -d "${retained[0]}" ]]
  [[ "$(stat -c %a "${retained[0]}")" == 700 ]]
  [[ -f "${retained[0]}/db-stop.log" ]]
}

check_case 23 0 23 0 'stopping disposable database'
check_case 7 7 23 0 'stopping disposable database'
check_case 1 0 0 1 'confirming database shutdown'

success_dir="$fixture_dir/success"
mkdir "$success_dir"
success_output="$(env TMPDIR="$success_dir" PATH="$fixture_dir/bin:$PATH" \
  CONTRACT_TEST_REAL_RUBY="$(command -v ruby)" \
  CONTRACT_FAKE_PRODUCER_STATUS=0 CONTRACT_FAKE_STOP_STATUS=0 CONTRACT_FAKE_PROBE_STATUS=0 \
  "$repo_root/tests/contracts/storage_group_snapshot_v4/run.sh" 2>&1)"
[[ "$success_output" == *'contract passed'* ]]
shopt -s nullglob
removed=("$success_dir"/storage-group-v4.*)
[[ "${#removed[@]}" == 0 ]]

printf 'storage group v4 teardown failure checks passed\n'
