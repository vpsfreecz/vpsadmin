#!/usr/bin/env bash
# Usage: $0 <nixpkgs | _nopkg> <gem name> <build id> <os build id>

set -x
set -e

PKGS="$1"
GEMDIR="$2"
GEM="$(basename $2)"

export VPSADMIN_BUILD_ID="$3"
export OS_BUILD_ID="$4"

pushd "$GEMDIR"
[ -f Gemfile.lock ] && rm -f Gemfile.lock
bundle install
pkg=$(bundle exec rake build | grep -oP "pkg/.+\.gem")
version=$(echo $pkg | grep -oP "\d+\.\d+\.\d+.*[^.gem]")

gem inabox "$pkg"

[ "$PKGS" == "_nopkg" ] && exit

popd
pushd "$PKGS/$GEM"
rm -f Gemfile.lock gemset.nix
sed -ri "s/gem '$GEM'[^$]*/gem '$GEM', '$version'/" Gemfile

bundix -l
