#!/bin/sh
# Assemble a netbird ipk without the OpenWrt SDK.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: build-netbird-ipk.sh --arch <aarch64_generic|x86_64> --version <v> \
         --binary <path> --license <path> --outdir <dir> \
         [--pkg-release N] [--source-date-epoch N] [--notices <path>]
EOF
	exit 2
}

arch= version= binary= license= notices= outdir=
pkg_release=1
epoch=
while [ $# -gt 0 ]; do
	case "$1" in
		--arch) arch=$2; shift 2 ;;
		--version) version=$2; shift 2 ;;
		--binary) binary=$2; shift 2 ;;
		--license) license=$2; shift 2 ;;
		--notices) notices=$2; shift 2 ;;
		--outdir) outdir=$2; shift 2 ;;
		--pkg-release) pkg_release=$2; shift 2 ;;
		--source-date-epoch) epoch=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$arch" ] && [ -n "$version" ] && [ -n "$binary" ] && [ -n "$license" ] && [ -n "$outdir" ] || usage
case "$arch" in
	aarch64_generic|x86_64) ;;
	*) echo "unsupported arch: $arch" >&2; exit 2 ;;
esac

case "$version" in
	*[!0-9.]*|*..*|'') echo "invalid version: $version" >&2; exit 2 ;;
esac
case "$pkg_release" in
	*[!0-9]*|'') echo "invalid pkg release: $pkg_release" >&2; exit 2 ;;
esac
[ -n "$epoch" ] || epoch=${SOURCE_DATE_EPOCH:-}
case "$epoch" in
	*[!0-9]*|'') echo "SOURCE_DATE_EPOCH or --source-date-epoch required" >&2; exit 2 ;;
esac

[ -f "$binary" ] && [ -x "$binary" ] || { echo "binary missing or not executable: $binary" >&2; exit 1; }
[ -f "$license" ] || { echo "license missing: $license" >&2; exit 1; }
if [ -n "$notices" ] && [ ! -f "$notices" ]; then
	echo "notices missing: $notices" >&2
	exit 1
fi

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(dirname "$script_dir")
init_script=$repo_root/packaging/netbird/netbird.init
control_in=$repo_root/packaging/netbird/control.in
[ -f "$init_script" ] || { echo "missing $init_script" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

mkdir -p "$work/data/usr/bin" "$work/data/etc/init.d" \
	"$work/data/usr/share/licenses/netbird" "$work/control"
cp "$binary" "$work/data/usr/bin/netbird"
chmod 0755 "$work/data/usr/bin/netbird"
cp "$init_script" "$work/data/etc/init.d/netbird"
chmod 0755 "$work/data/etc/init.d/netbird"
cp "$license" "$work/data/usr/share/licenses/netbird/LICENSE"
chmod 0644 "$work/data/usr/share/licenses/netbird/LICENSE"
if [ -n "$notices" ]; then
	cp "$notices" "$work/data/usr/share/licenses/netbird/THIRD-PARTY-NOTICES.txt"
	chmod 0644 "$work/data/usr/share/licenses/netbird/THIRD-PARTY-NOTICES.txt"
fi

installed_size=$(du -sk "$work/data" | awk '{print $1}')
sed \
	-e "s|@VERSION@|$version|g" \
	-e "s|@PKG_RELEASE@|$pkg_release|g" \
	-e "s|@ARCH@|$arch|g" \
	-e "s|@INSTALLED_SIZE@|$installed_size|g" \
	-e "s|@SOURCE_DATE_EPOCH@|$epoch|g" \
	"$control_in" > "$work/control/control"

tar_opts="--sort=name --mtime=@$epoch --owner=0 --group=0 --numeric-owner"

# shellcheck disable=SC2086
tar -C "$work/control" $tar_opts -cf - ./control | gzip -9n > "$work/control.tar.gz"
# shellcheck disable=SC2086
tar -C "$work/data" $tar_opts -cf - ./usr ./etc | gzip -9n > "$work/data.tar.gz"
printf '2.0\n' > "$work/debian-binary"

mkdir -p "$outdir"
ipk="$outdir/netbird_${version}-r${pkg_release}_${arch}.ipk"
# shellcheck disable=SC2086
tar -C "$work" $tar_opts -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -9n > "$ipk"
( cd "$outdir" && sha256sum "$(basename "$ipk")" > "$(basename "$ipk").sha256" )
echo "built $ipk"
