#!/bin/sh
# Usage: run from repository root

set -e
pushd packages/api

cat ../../api/Gemfile | sed '/^### vpsAdmin plugin marker ###$/,$d' > Gemfile

for f in ../../plugins/*/api/Gemfile ; do
	echo "# Plugin $(basename $(realpath $(dirname $f)/../))" >> Gemfile
	cat $f >> Gemfile
done

bundix -l

popd
