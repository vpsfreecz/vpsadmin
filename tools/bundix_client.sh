#!/usr/bin/env bash
# Usage: run from repository root

set -e
export TMPDIR=/tmp
pushd packages/client
rm -f Gemfile.lock
bundix -l
popd
