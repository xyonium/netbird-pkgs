#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Verify a built luci-app-netbird ipk against the version env and the payload
# contract this repository depends on.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: verify-luci-ipk.sh --ipk <path> --version-env <file>
EOF
	exit 2
}

ipk= version_env=
while [ $# -gt 0 ]; do
	case "$1" in
		--ipk) ipk=$2; shift 2 ;;
		--version-env) version_env=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$ipk" ] && [ -n "$version_env" ] || usage
[ -f "$ipk" ] || { echo "no such ipk: $ipk" >&2; exit 1; }
[ -f "$version_env" ] || { echo "no such version env: $version_env" >&2; exit 1; }

# Parse the version env instead of sourcing it: the release step must not
# depend on the caller's shell having exported these values.
version=$(sed -n 's/^LUCI_VERSION=//p' "$version_env" | head -n 1)
release=$(sed -n 's/^LUCI_PKG_RELEASE=//p' "$version_env" | head -n 1)
[ -n "$version" ] && [ -n "$release" ] \
	|| { echo "version env lacks LUCI_VERSION/LUCI_PKG_RELEASE: $version_env" >&2; exit 1; }
want="${version}-r${release}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/control" "$work/root"

fail=0
note_fail() { echo "FAIL: $*" >&2; fail=1; }

tar -xzf "$ipk" -C "$work"
members=$(tar tzf "$ipk" | sed 's|^\./||' | sort)
expected=$(printf '%s\n' debian-binary control.tar.gz data.tar.gz | sort)
[ "$members" = "$expected" ] || note_fail "unexpected archive members: $members"
[ -f "$work/control.tar.gz" ] || { echo "missing control.tar.gz" >&2; exit 1; }
[ -f "$work/data.tar.gz" ] || { echo "missing data.tar.gz" >&2; exit 1; }
tar -xzf "$work/control.tar.gz" -C "$work/control"
tar -xzf "$work/data.tar.gz" -C "$work/root"

control="$work/control/control"
[ -f "$control" ] || { echo "missing control" >&2; exit 1; }

grep -q '^Package: luci-app-netbird$' "$control" || note_fail "Package is not luci-app-netbird"
grep -q '^Architecture: all$' "$control" || note_fail "Architecture is not all"
got=$(sed -n 's/^Version: //p' "$control" | head -n 1)
[ "$got" = "$want" ] || note_fail "Version is '$got', version env wants '$want'"

# The payload is the whole point of the package: an augmentation step that
# only rewraps the documents would silently drop every installed file.
bin_config="$work/root/etc/config/netbird_bin"
if [ ! -f "$bin_config" ]; then
	note_fail "payload is missing etc/config/netbird_bin (package data was lost)"
elif ! grep -q "option binary_source 'opkg'" "$bin_config"; then
	note_fail "binary_source default is not opkg in etc/config/netbird_bin"
fi
for doc in LICENSE NOTICE; do
	[ -f "$work/root/usr/share/doc/luci-app-netbird/$doc" ] \
		|| note_fail "payload is missing usr/share/doc/luci-app-netbird/$doc"
done

# 0002 moves the app from Services into the VPN category; make sure the shipped
# menu still carries that, not the upstream default.
menu="$work/root/usr/share/luci/menu.d/luci-app-netbird.json"
if [ ! -f "$menu" ]; then
	note_fail "payload is missing usr/share/luci/menu.d/luci-app-netbird.json"
elif ! grep -q '"admin/vpn/netbird"' "$menu"; then
	note_fail "menu entry is not under VPN (expected admin/vpn/netbird)"
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "ok: luci ipk verified: $ipk ($want)"
