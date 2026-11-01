#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Derive a reproducible SOURCE_DATE_EPOCH from the commit that pinned a version.
#
# A shallow clone has no parent commits, so git treats the checkout as a root
# commit and reports HEAD's timestamp for every path. That value changes with
# every unrelated commit, which silently makes rebuilds non-reproducible, so
# refuse to answer instead.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: source-date-epoch.sh --env-file <file>
EOF
	exit 2
}

env_file=
while [ $# -gt 0 ]; do
	case "$1" in
		--env-file) env_file=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$env_file" ] || usage
[ -f "$env_file" ] || { echo "no such version env: $env_file" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository" >&2; exit 1; }

if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo unknown)" != "false" ]; then
	echo "refusing to derive SOURCE_DATE_EPOCH from a shallow clone: git would report HEAD's" >&2
	echo "timestamp for every path instead of the commit that pinned $env_file." >&2
	echo "check out with fetch-depth: 0." >&2
	exit 1
fi

epoch=$(git log -1 --format=%ct -- "$env_file" 2>/dev/null) || epoch=
[ -n "$epoch" ] || { echo "no commit touches $env_file; cannot derive SOURCE_DATE_EPOCH" >&2; exit 1; }

printf '%s\n' "$epoch"
