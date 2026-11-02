#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Install a pinned OpenWrt SDK and prepare it for building a LuCI package.
#
# A bare SDK ships no feeds, and luci-app-netbird includes feeds/luci/luci.mk;
# luci-base additionally supplies the po2lmo host tool that the i18n subpackage
# compiles with. Both steps are needed before `package/<name>/compile` works.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: install-openwrt-sdk.sh --version <v> --sha256 <hex> --dest <dir> \
         [--arch x86/64] [--tarball <file>]
EOF
	exit 2
}

version= sha256= dest= arch=x86/64 tarball=
while [ $# -gt 0 ]; do
	case "$1" in
		--version) version=$2; shift 2 ;;
		--sha256) sha256=$2; shift 2 ;;
		--dest) dest=$2; shift 2 ;;
		--arch) arch=$2; shift 2 ;;
		--tarball) tarball=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$version" ] && [ -n "$sha256" ] && [ -n "$dest" ] || usage
case "$sha256" in
	*[!0-9a-f]*|'') echo "invalid sha256: $sha256" >&2; exit 2 ;;
esac
[ "${#sha256}" -eq 64 ] || { echo "sha256 must be 64 hex chars: $sha256" >&2; exit 2; }

name="openwrt-sdk-${version}-$(printf '%s' "$arch" | tr '/' '-')_gcc-13.3.0_musl.Linux-x86_64.tar.zst"

if [ -n "$tarball" ]; then
	[ -f "$tarball" ] || { echo "no such tarball: $tarball" >&2; exit 1; }
else
	tarball=$(mktemp)
	trap 'rm -f "$tarball"' EXIT INT TERM
	curl -fsSL "https://downloads.openwrt.org/releases/${version}/targets/${arch}/${name}" \
		-o "$tarball"
fi

echo "${sha256}  ${tarball}" | sha256sum -c - >/dev/null \
	|| { echo "SDK checksum mismatch for ${name}" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest"
tar --zstd -xf "$tarball" -C "$dest" --strip-components=1
[ -x "$dest/scripts/feeds" ] || { echo "not an SDK tree: $dest" >&2; exit 1; }

(
	cd "$dest"
	./scripts/feeds update -a >/dev/null
	./scripts/feeds install luci-base >/dev/null
)
echo "sdk ready: $dest ($version)"
