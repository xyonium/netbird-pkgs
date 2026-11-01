#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Verify an assembled netbird ipk against the packaging contract.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: verify-ipk.sh --ipk <path> --arch <aarch64_generic|x86_64> \
         [--version <v>] [--skip-binary-check]

This verifier is for the netbird client ipk only. Use verify-luci-ipk.sh for
the luci-app-netbird package.
EOF
	exit 2
}

ipk= arch= version= skip=0
while [ $# -gt 0 ]; do
	case "$1" in
		--ipk) ipk=$2; shift 2 ;;
		--arch) arch=$2; shift 2 ;;
		--version) version=$2; shift 2 ;;
		--skip-binary-check) skip=1; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$ipk" ] && [ -n "$arch" ] || usage
[ -f "$ipk" ] || { echo "no such ipk: $ipk" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
mkdir -p "$work/control" "$work/root"

fail=0
note_fail() { echo "FAIL: $*" >&2; fail=1; }
note_ok() { echo "ok: $*"; }

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

grep -q '^Package: netbird$' "$control" || note_fail "Package is not netbird"
grep -q "^Architecture: $arch\$" "$control" || note_fail "Architecture is not $arch"
grep -q '^Depends:.*kmod-wireguard' "$control" || note_fail "Depends lacks kmod-wireguard"
grep -q '^Depends:.*ca-bundle' "$control" || note_fail "Depends lacks ca-bundle"

( cd "$work/root" && find . -type f | sed 's|^\./||' ) > "$work/files"
while IFS= read -r f; do
	case "$f" in
		usr/bin/netbird|etc/init.d/netbird|usr/share/licenses/netbird/*) ;;
		*) note_fail "unexpected file in package: /$f" ;;
	esac
done < "$work/files"

[ -f "$work/root/usr/bin/netbird" ] || note_fail "missing /usr/bin/netbird"
[ -x "$work/root/usr/bin/netbird" ] || note_fail "/usr/bin/netbird is not executable"
[ -f "$work/root/etc/init.d/netbird" ] || note_fail "missing /etc/init.d/netbird"
if [ -f "$work/root/etc/init.d/netbird" ]; then
	sh -n "$work/root/etc/init.d/netbird" || note_fail "init script has a syntax error"
fi

if [ "$skip" -eq 0 ]; then
	if [ -f "$work/root/usr/bin/netbird" ]; then
		file "$work/root/usr/bin/netbird" | grep -q 'statically linked' \
			|| note_fail "binary is not statically linked"
		case "$arch" in
			x86_64) file "$work/root/usr/bin/netbird" | grep -Eq 'x86-64|X86-64' \
				|| note_fail "binary is not x86-64" ;;
			aarch64_generic) file "$work/root/usr/bin/netbird" | grep -q 'ARM aarch64\|AArch64' \
				|| note_fail "binary is not aarch64" ;;
		esac
		if command -v readelf >/dev/null 2>&1; then
			if readelf -l "$work/root/usr/bin/netbird" 2>/dev/null | grep -q 'INTERP'; then
				note_fail "binary has an INTERP segment"
			fi
		fi
		if [ -n "$version" ] && [ "$arch" = x86_64 ]; then
			got=$("$work/root/usr/bin/netbird" version 2>&1 | head -n 1)
			[ "$got" = "$version" ] || note_fail "binary reports '$got', expected '$version'"
		fi
	fi
fi

if [ "$fail" -ne 0 ]; then
	exit 1
fi
note_ok "ipk verified: $ipk"
