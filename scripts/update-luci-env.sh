#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Sync the upstream luci-app-netbird Makefile into versions/luci-app-netbird.env.
#
# Two things this must not do:
#   - rewrite the whole file, which would drop the pinned SDK fields;
#   - adopt upstream's PKG_RELEASE, which would walk our own release number
#     backwards (and below upstream's) so opkg upgrade would skip our build.
# Our release number only ever moves forward, and only when upstream moves.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: update-luci-env.sh --env-file <file> --commit <sha> --makefile <path>
EOF
	exit 2
}

env_file= commit= makefile=
while [ $# -gt 0 ]; do
	case "$1" in
		--env-file) env_file=$2; shift 2 ;;
		--commit) commit=$2; shift 2 ;;
		--makefile) makefile=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$env_file" ] && [ -n "$commit" ] && [ -n "$makefile" ] || usage
[ -f "$makefile" ] || { echo "no such Makefile: $makefile" >&2; exit 1; }

pkg_version=$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)
pkg_release=$(sed -n 's/^PKG_RELEASE:=//p' "$makefile" | head -n 1)
[ -n "$pkg_version" ] && [ -n "$pkg_release" ] \
	|| { echo "Makefile does not pin PKG_VERSION/PKG_RELEASE: $makefile" >&2; exit 1; }

get() { sed -n "s/^$1=//p" "$env_file" 2>/dev/null | head -n 1; }
put() {
	if grep -q "^$1=" "$env_file" 2>/dev/null; then
		sed -i "s|^$1=.*|$1=$2|" "$env_file"
	else
		printf '%s=%s\n' "$1" "$2" >> "$env_file"
	fi
}

cur_version=$(get LUCI_VERSION)
cur_commit=$(get LUCI_COMMIT)
cur_release=$(get LUCI_PKG_RELEASE)
cur_upstream=$(get LUCI_UPSTREAM_RELEASE)

if [ "$cur_version" = "$pkg_version" ] && [ "$cur_commit" = "$commit" ] \
	&& [ "$cur_upstream" = "$pkg_release" ]; then
	echo "CHANGED=0"
	exit 0
fi

# Release number: strictly greater than both our previous one and upstream's,
# so a device running either never considers our build older.
case "$cur_release" in *[!0-9]*|'') cur_release=0 ;; esac
case "$pkg_release" in *[!0-9]*|'') pkg_release=0 ;; esac
next_release=$cur_release
[ "$pkg_release" -gt "$next_release" ] && next_release=$pkg_release
next_release=$((next_release + 1))

put LUCI_VERSION "$pkg_version"
put LUCI_COMMIT "$commit"
put LUCI_UPSTREAM_RELEASE "$pkg_release"
put LUCI_PKG_RELEASE "$next_release"
echo "CHANGED=1"
