#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Resolve the latest netbird release without mutating the repo.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: resolve-upstream.sh --repo <owner/name> --fixture <release.json> \
         --tarball <file> [--env-file versions/netbird.env]
EOF
	exit 2
}

repo= fixture= tarball= env_file= commit_override=
while [ $# -gt 0 ]; do
	case "$1" in
		--repo) repo=$2; shift 2 ;;
		--fixture) fixture=$2; shift 2 ;;
		--tarball) tarball=$2; shift 2 ;;
		--env-file) env_file=$2; shift 2 ;;
		--commit) commit_override=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$repo" ] && [ -n "$fixture" ] && [ -n "$tarball" ] || usage
[ -f "$fixture" ] || { echo "missing fixture: $fixture" >&2; exit 1; }
[ -f "$tarball" ] || { echo "missing tarball: $tarball" >&2; exit 1; }

tag=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$fixture" | head -n 1)
commit=$commit_override
[ -n "$commit" ] || commit=$(sed -n 's/.*"target_commitish"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$fixture" | head -n 1)
[ -n "$tag" ] || { echo "fixture has no tag_name" >&2; exit 1; }

version=${tag#v}
sha=$(sha256sum "$tarball" | awk '{print $1}')

changed=1
if [ -n "$env_file" ] && [ -f "$env_file" ]; then
	current=$(sed -n 's/^NETBIRD_VERSION=//p' "$env_file" | head -n 1)
	current_sha=$(sed -n 's/^NETBIRD_SHA256=//p' "$env_file" | head -n 1)
	if [ "$current" = "$version" ] && [ "$current_sha" = "$sha" ]; then
		changed=0
	fi
fi

printf 'VERSION=%s\nCOMMIT=%s\nSHA256=%s\nCHANGED=%s\n' "$version" "$commit" "$sha" "$changed"
