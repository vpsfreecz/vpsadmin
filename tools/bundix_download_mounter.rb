#!/bin/sh
# Usage: run from repository root

set -e
pushd packages/download-mounter
cp -pf ../../download_mounter/Gemfile .
bundix -l
popd
