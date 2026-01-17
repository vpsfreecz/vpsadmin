#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname "$0")" && pwd)"
OS_ROOT="${VPSADMINOS_PATH:-${ROOT}/../vpsadminos}"

if [ ! -d "$OS_ROOT" ]; then
  echo "vpsadminos repository not found at $OS_ROOT. Set VPSADMINOS_PATH to override." >&2
  exit 1
fi

mkdir -p "$ROOT/result"
nix-build --out-link "$ROOT/result/test-runner" "$OS_ROOT/os/packages/test-runner/entry.nix" >/dev/null
exec "$ROOT/result/test-runner/bin/test-runner" "$@"
