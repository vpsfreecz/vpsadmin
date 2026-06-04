#!/usr/bin/env bash

set -euo pipefail

usage() {
	cat <<'EOF'
Usage: tools/update_vpsadminos_flake.sh [flake-url]

Update the vpsadminos flake input and commit the isolated flake.lock change as:

  flake: vpsadminos <old9> -> <new9>

With no argument, update vpsadminos from the flake input URL. With flake-url,
pin vpsadminos to that exact flake URL while leaving flake.nix unchanged.

The script refuses to start with tracked changes present and refuses to
commit if the update modifies anything other than flake.lock.
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

vpsadminos_rev() {
	nix flake metadata --json . \
		| jq -er '.locks.nodes.vpsadminos.locked.rev'
}

short_rev() {
	printf '%s' "$1" | cut -c1-9
}

changed_files() {
	git diff --name-only
}

staged_files() {
	git diff --cached --name-only
}

update_vpsadminos() {
	local flake_url="${1:-}"
	local tmp_lock

	if [ -z "$flake_url" ]; then
		nix flake update vpsadminos
		return
	fi

	tmp_lock="$(mktemp)"
	trap 'rm -f "$tmp_lock"' RETURN

	nix flake update vpsadminos \
		--override-input vpsadminos "$flake_url" \
		--output-lock-file "$tmp_lock"
	mv "$tmp_lock" flake.lock

	trap - RETURN
}

case "${1:-}" in
	-h|--help)
		usage
		exit 0
		;;
	*)
		if [ "$#" -gt 1 ]; then
			usage >&2
			exit 1
		fi
		;;
esac

require_cmd git
require_cmd jq
require_cmd nix

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

[ -f flake.lock ] || die "flake.lock not found in $repo_root"

if ! git diff --quiet || ! git diff --cached --quiet; then
	die "tracked worktree changes are present; commit or stash them first"
fi

old_rev="$(vpsadminos_rev)"
old_short="$(short_rev "$old_rev")"

printf 'Current vpsadminos revision: %s\n' "$old_rev"
update_vpsadminos "${1:-}"

mapfile -t changed < <(changed_files)

case "${#changed[@]}" in
	0)
		printf 'vpsadminos is already up to date at %s\n' "$old_rev"
		exit 0
		;;
	1)
		[ "${changed[0]}" = "flake.lock" ] || {
			printf 'Unexpected changed file:\n' >&2
			printf '  %s\n' "${changed[@]}" >&2
			exit 1
		}
		;;
	*)
		printf 'Unexpected changed files:\n' >&2
		printf '  %s\n' "${changed[@]}" >&2
		exit 1
		;;
esac

new_rev="$(vpsadminos_rev)"
new_short="$(short_rev "$new_rev")"

if [ "$old_rev" = "$new_rev" ]; then
	die "flake.lock changed, but vpsadminos remained at $old_rev"
fi

subject="flake: vpsadminos ${old_short} -> ${new_short}"
commit_msg="$(mktemp)"
trap 'rm -f "$commit_msg"' EXIT
printf '%s\n' "$subject" >"$commit_msg"

git add flake.lock
mapfile -t staged < <(staged_files)

if [ "${#staged[@]}" -ne 1 ] || [ "${staged[0]}" != "flake.lock" ]; then
	printf 'Unexpected staged files:\n' >&2
	printf '  %s\n' "${staged[@]}" >&2
	exit 1
fi

git commit -F "$commit_msg"
printf 'Committed: %s\n' "$subject"
