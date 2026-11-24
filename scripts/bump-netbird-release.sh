#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Increment NETBIRD_PKG_RELEASE in a versions file and print the new value.
#
# The release tag is v<netbird version>-r<pkg release>, and sign-publish leaves an
# existing tag alone, so a LuCI-only change cannot ride on the tag that is already
# out. Bumping the package release is what makes a new tag, and therefore a new
# set of published artifacts. upstream-watch writes 1 again the next time netbird
# itself moves, so the number does not grow without bound.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: bump-netbird-release.sh --env-file <file>
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
[ -f "$env_file" ] || { echo "no such file: $env_file" >&2; exit 1; }

current=$(sed -n 's/^NETBIRD_PKG_RELEASE=//p' "$env_file" | head -n 1)
[ -n "$current" ] || { echo "NETBIRD_PKG_RELEASE is not set in $env_file" >&2; exit 1; }
case "$current" in
	*[!0-9]*) echo "NETBIRD_PKG_RELEASE is not a number: $current" >&2; exit 1 ;;
esac

next=$((current + 1))
sed -i "s/^NETBIRD_PKG_RELEASE=.*/NETBIRD_PKG_RELEASE=$next/" "$env_file"
grep -qx "NETBIRD_PKG_RELEASE=$next" "$env_file" \
	|| { echo "failed to update $env_file" >&2; exit 1; }

echo "NETBIRD_PKG_RELEASE=$next"
