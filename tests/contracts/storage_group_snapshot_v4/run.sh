#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

repo_root="$(cd "$(dirname "$0")/../../.." && pwd -P)"
cd "$repo_root"

private_dir="$(mktemp -d "${TMPDIR:-/tmp}/storage-group-v4.XXXXXXXX")"
stage='initializing test runner'
export VPSADMIN_TEST_DB_STATE_DIR="$private_dir/db"
export VPSADMIN_TEST_DB_NAME="storage_group_$(ruby -rsecurerandom -e 'print SecureRandom.hex(6)')"
export VPSADMIN_TEST_DB_PORT
VPSADMIN_TEST_DB_PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); print server.addr[1]; server.close')"

cleanup() {
  test_status=$?
  trap - EXIT
  stop_status=0
  nix develop .#api -c "$repo_root/tools/test-db" stop >"$private_dir/db-stop.log" 2>&1 || stop_status=$?
  probe_status=0
  if ((stop_status == 0)); then
    ruby -rsocket -e '
      begin
        Socket.tcp("127.0.0.1", Integer(ENV.fetch("VPSADMIN_TEST_DB_PORT")), connect_timeout: 2) { }
        exit 1
      rescue Errno::ECONNREFUSED
        exit 0
      rescue StandardError
        exit 2
      end
    ' >"$private_dir/db-stop-probe.log" 2>&1 || probe_status=$?
  fi

  if ((stop_status != 0 || probe_status != 0)); then
    if ((stop_status != 0)); then
      teardown_stage='stopping disposable database'
      teardown_status=$stop_status
    else
      teardown_stage='confirming database shutdown'
      teardown_status=$probe_status
    fi
    printf 'storage group v4 contract failed at %s (exit %s); private diagnostics: %s\n' \
      "$teardown_stage" "$teardown_status" "$private_dir" >&2
    if ((test_status != 0)); then
      printf 'earlier test failure at %s (exit %s)\n' "$stage" "$test_status" >&2
      exit "$test_status"
    fi
    exit "$teardown_status"
  fi

  if ((test_status != 0)); then
    printf 'storage group v4 contract failed at %s (exit %s); private diagnostics: %s\n' \
      "$stage" "$test_status" "$private_dir" >&2
    case "$stage" in
      'API producer') safe_spec_summary "$private_dir/api-producer.log" >&2 ;;
      'NodeCtld consumer') safe_spec_summary "$private_dir/node-consumer.log" >&2 ;;
    esac
    exit "$test_status"
  fi

  safe_spec_summary "$private_dir/api-producer.log"
  safe_spec_summary "$private_dir/node-consumer.log"
  if ! rm -rf -- "$private_dir"; then
    printf 'storage group v4 contract failed during private cleanup\n' >&2
    exit 1
  fi
  printf 'storage group v4 contract passed in %ss\n' "$((SECONDS - started_at))"
}

safe_spec_summary() {
  test -f "$1" || return 0
  grep -E '^[0-9]+ examples?, [0-9]+ failures?(, [0-9]+ pending)?$' "$1" | tail -n 1 || true
}
trap cleanup EXIT

started_at="$SECONDS"
# tools/test-db start and url print a disposable credential-bearing URL. Keep
# both commands' output inside the private directory and never enable xtrace.
stage='starting disposable database'
nix develop .#api -c "$repo_root/tools/test-db" start >"$private_dir/db-start.log" 2>&1
stage='reading private database URL'
database_url="$("$repo_root/tools/test-db" url 2>"$private_dir/db-url.log")"
test -n "$database_url"
stage='validating private database URL'
env DATABASE_URL="$database_url" ruby -ruri -e '
  begin
    url = URI.parse(ENV.fetch("DATABASE_URL"))
    valid = url.scheme == "mysql2" && url.host == "127.0.0.1" &&
            url.port.to_s == ENV.fetch("VPSADMIN_TEST_DB_PORT") &&
            url.path == "/#{ENV.fetch("VPSADMIN_TEST_DB_NAME")}" &&
            !url.user.to_s.empty? && !url.password.to_s.empty?
    abort "invalid disposable DB URL" unless valid
  rescue URI::InvalidURIError
    abort "invalid disposable DB URL"
  end
'

stage='API producer'
env DATABASE_URL="$database_url" CONTRACT_PRIVATE_DIR="$private_dir" CONTRACT_REPO_ROOT="$repo_root" \
  RACK_ENV=test VPSADMIN_PLUGINS=none VPSADMIN_TEST_DB_AUTO=0 \
  nix develop .#api -c bash -c \
  'cd "$CONTRACT_REPO_ROOT/api" && bundle exec rspec --options /dev/null --require spec_helper ../tests/contracts/storage_group_snapshot_v4/api_producer_spec.rb' \
  >"$private_dir/api-producer.log" 2>&1

stage='NodeCtld consumer'
env DATABASE_URL="$database_url" CONTRACT_PRIVATE_DIR="$private_dir" CONTRACT_REPO_ROOT="$repo_root" \
  RACK_ENV=test VPSADMIN_TEST_DB_AUTO=0 \
  nix develop .#libnodectld -c bash -c \
  'set -euo pipefail
   cd "$CONTRACT_REPO_ROOT/libnodectld"
   unset RUBYOPT
   export BUNDLE_PATH="$CONTRACT_PRIVATE_DIR/node-bundle"
   export BUNDLE_APP_CONFIG="$CONTRACT_PRIVATE_DIR/node-bundle-config"
   export BUNDLE_USER_HOME="$CONTRACT_PRIVATE_DIR/node-bundle-user"
   export BUNDLE_DISABLE_SHARED_GEMS=true
   bundle install >"$CONTRACT_PRIVATE_DIR/node-bundle-install.log" 2>&1
   bundle exec rspec --options /dev/null ../tests/contracts/storage_group_snapshot_v4/node_consumer_spec.rb' \
  >"$private_dir/node-consumer.log" 2>&1

stage='complete'
