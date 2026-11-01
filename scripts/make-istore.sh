#!/bin/sh
# Build the PR-ready iStoreOS bundle from locally built ipks.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: make-istore.sh --ipk-dir <dir> --outdir <dir> --version <v> --pkg-release <n>
EOF
	exit 2
}

ipk_dir= outdir= version= release=
while [ $# -gt 0 ]; do
	case "$1" in
		--ipk-dir) ipk_dir=$2; shift 2 ;;
		--outdir) outdir=$2; shift 2 ;;
		--version) version=$2; shift 2 ;;
		--pkg-release) release=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$ipk_dir" ] && [ -n "$outdir" ] && [ -n "$version" ] && [ -n "$release" ] || usage
[ -d "$ipk_dir" ] || { echo "missing ipk dir: $ipk_dir" >&2; exit 1; }

src_a53="$ipk_dir/netbird_${version}-r${release}_aarch64_generic.ipk"
src_x86="$ipk_dir/netbird_${version}-r${release}_x86_64.ipk"
[ -f "$src_a53" ] || { echo "missing $src_a53" >&2; exit 1; }
[ -f "$src_x86" ] || { echo "missing $src_x86" >&2; exit 1; }

luci=$(find "$ipk_dir" -maxdepth 1 -name 'luci-app-netbird_*_all.ipk' | head -n 1)
i18n=$(find "$ipk_dir" -maxdepth 1 -name 'luci-i18n-netbird-zh-cn_*_all.ipk' | head -n 1)
[ -n "$luci" ] || { echo "missing luci-app-netbird ipk" >&2; exit 1; }

script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(dirname "$script_dir")
meta_src="$repo_root/packaging/istore/app-meta-netbird"
[ -f "$meta_src/Makefile" ] || { echo "missing metadata template" >&2; exit 1; }

epoch=${SOURCE_DATE_EPOCH:-0}
tar_opts="--sort=name --mtime=@$epoch --owner=0 --group=0 --numeric-owner"

mkdir -p "$outdir/bin/packages/aarch64_cortex-a53/nas" \
	"$outdir/bin/packages/x86_64/nas" \
	"$outdir/bin/packages/all/nas_luci" \
	"$outdir/applications/app-meta-netbird"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
tar -xzf "$src_a53" -C "$work"
mkdir -p "$work/control"
tar -xzf "$work/control.tar.gz" -C "$work/control"
sed -i 's/^Architecture: .*/Architecture: aarch64_cortex-a53/' "$work/control/control"
# shellcheck disable=SC2086
tar -C "$work/control" $tar_opts -cf - ./control | gzip -9n > "$work/control.tar.gz"
a53_ipk="$outdir/bin/packages/aarch64_cortex-a53/nas/netbird_${version}-r${release}_aarch64_cortex-a53.ipk"
# shellcheck disable=SC2086
tar -C "$work" $tar_opts -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -9n > "$a53_ipk"

cp "$src_x86" "$outdir/bin/packages/x86_64/nas/"
cp "$luci" "$outdir/bin/packages/all/nas_luci/"
[ -z "$i18n" ] || cp "$i18n" "$outdir/bin/packages/all/nas_luci/"

sed -e "s|@VERSION@|$version|g" -e "s|@RELEASE@|$release|g" \
	"$meta_src/Makefile" > "$outdir/applications/app-meta-netbird/Makefile"
cp "$meta_src/logo.png" "$outdir/applications/app-meta-netbird/logo.png"

# Validate the repacked Architecture against its directory.
got=$(tar -xOf "$a53_ipk" ./control.tar.gz | tar -xzOf - ./control | sed -n 's/^Architecture: //p')
[ "$got" = aarch64_cortex-a53 ] || { echo "repack failed: Architecture=$got" >&2; exit 1; }

echo "iStore bundle ready: $outdir"
