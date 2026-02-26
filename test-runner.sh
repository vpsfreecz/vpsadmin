#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname "$0")" && pwd)"
cd "$ROOT"

exec nix run .#test-runner -- "$@"
