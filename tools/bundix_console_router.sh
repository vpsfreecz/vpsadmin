#!/bin/sh
# Usage: run from repository root

set -e
export TMPDIR=/tmp
pushd packages/console-router
rm -f Gemfile.lock
cp -pf ../../console_router/Gemfile .
bundix -l
popd
