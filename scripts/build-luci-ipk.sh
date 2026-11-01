#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Build luci-app-netbird from a pinned source tree with the binary_source patch.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: build-luci-ipk.sh --source <dir> --version <v> --release <r> --outdir <dir> \
         [--sdk <sdk-dir>] [--patch-only]
EOF
	exit 2
}

source_dir= sdk= version= release= outdir= patch_only=0
while [ $# -gt 0 ]; do
	case "$1" in
		--source) source_dir=$2; shift 2 ;;
		--sdk) sdk=$2; shift 2 ;;
		--version) version=$2; shift 2 ;;
		--release) release=$2; shift 2 ;;
		--outdir) outdir=$2; shift 2 ;;
		--patch-only) patch_only=1; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$source_dir" ] && [ -n "$version" ] && [ -n "$release" ] && [ -n "$outdir" ] || usage
[ -d "$source_dir" ] || { echo "missing source: $source_dir" >&2; exit 1; }
[ -f "$source_dir/root/etc/config/netbird_bin" ] \
	|| { echo "source has no root/etc/config/netbird_bin: $source_dir" >&2; exit 1; }

script_dir=$(cd "$(dirname "$0")" && pwd)
patch_file="$script_dir/../packaging/luci-app-netbird/patches/0001-default-binary-source-opkg.patch"
[ -f "$patch_file" ] || { echo "missing patch: $patch_file" >&2; exit 1; }

if ! patch -p1 -d "$source_dir" --dry-run -i "$patch_file" >/dev/null 2>&1; then
	echo "patch does not apply (already applied or upstream diverged): $patch_file" >&2
	exit 1
fi
patch -p1 -d "$source_dir" -i "$patch_file" >/dev/null || { echo "patch failed" >&2; exit 1; }

if [ "$patch_only" -eq 1 ]; then
	echo "patched $source_dir"
	exit 0
fi

[ -n "$sdk" ] && [ -d "$sdk" ] || { echo "missing SDK dir: ${sdk:-unset}" >&2; exit 1; }
[ -n "$outdir" ] || usage
mkdir -p "$outdir"

dest="$sdk/package/luci-app-netbird"
rm -rf "$dest"
mkdir -p "$dest"
cp -a "$source_dir/." "$dest/"

make -C "$sdk" package/luci-app-netbird/compile V=s

ipk=$(find "$sdk/bin/packages" -name "luci-app-netbird_${version}-r${release}_all.ipk" | head -n 1)
[ -n "$ipk" ] || { echo "luci-app-netbird ipk not produced" >&2; exit 1; }

# Add the upstream license files to the package data, since luci.mk does not.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
tar -xzf "$ipk" -C "$work"
# Unpack the SDK payload before adding files, otherwise the rewrapped
# data.tar.gz would contain the documents alone.
mkdir -p "$work/data"
tar -xzf "$work/data.tar.gz" -C "$work/data"
mkdir -p "$work/data/usr/share/doc/luci-app-netbird"
for f in LICENSE NOTICE; do
	[ -f "$dest/$f" ] && cp "$dest/$f" "$work/data/usr/share/doc/luci-app-netbird/$f"
done
epoch=${SOURCE_DATE_EPOCH:-0}
tar_opts="--sort=name --mtime=@$epoch --owner=0 --group=0 --numeric-owner"
data_entries=$(cd "$work/data" && find . -mindepth 1 -maxdepth 1)
# shellcheck disable=SC2086
tar -C "$work/data" $tar_opts -cf - $data_entries | gzip -9n > "$work/data.tar.gz"
out="$outdir/$(basename "$ipk")"
# shellcheck disable=SC2086
tar -C "$work" $tar_opts -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -9n > "$out"
( cd "$outdir" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256" )

echo "built $out"
