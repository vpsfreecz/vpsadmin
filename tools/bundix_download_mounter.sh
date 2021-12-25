#!/bin/sh
# Usage: run from repository root

set -e
pushd packages/download-mounter
rm -f Gemfile.lock
cp -pf ../../download_mounter/Gemfile .
bundix -l
popd
