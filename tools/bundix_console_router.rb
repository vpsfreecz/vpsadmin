#!/bin/sh
# Usage: run from repository root

set -e
pushd packages/console-router
cp -pf ../../console_router/Gemfile .
bundix -l
popd
