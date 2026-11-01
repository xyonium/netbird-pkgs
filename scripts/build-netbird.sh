#!/bin/sh
# Build the netbird client with the pinned toolchain and flags.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: build-netbird.sh --arch <aarch64_generic|x86_64> --version <v> \
         --commit <sha> --source <dir> --outdir <dir> [--dry-run]
EOF
	exit 2
}

arch= version= commit= source= outdir=
dry_run=0
while [ $# -gt 0 ]; do
	case "$1" in
		--arch) arch=$2; shift 2 ;;
		--version) version=$2; shift 2 ;;
		--commit) commit=$2; shift 2 ;;
		--source) source=$2; shift 2 ;;
		--outdir) outdir=$2; shift 2 ;;
		--dry-run) dry_run=1; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$arch" ] && [ -n "$version" ] && [ -n "$commit" ] && [ -n "$source" ] && [ -n "$outdir" ] || usage
case "$arch" in
	aarch64_generic) goarch=arm64 ;;
	x86_64) goarch=amd64 ;;
	*) echo "unsupported arch: $arch" >&2; exit 2 ;;
esac
[ -d "$source/client" ] || { echo "source tree missing ./client: $source" >&2; exit 1; }

case "${SOURCE_DATE_EPOCH:-}" in
	*[!0-9]*|'') echo "SOURCE_DATE_EPOCH must be set to a positive integer" >&2; exit 2 ;;
esac

GO=${GO:-go}
toolchain=$("$GO" version 2>/dev/null | awk '{print $3}') || {
	echo "cannot run $GO version" >&2
	exit 1
}
if [ "$toolchain" != "go1.26.2" ]; then
	echo "go1.26.2 required, found ${toolchain:-unknown}" >&2
	exit 1
fi

ldflags="-s -w \
-X github.com/netbirdio/netbird/version.version=$version \
-X main.commit=$commit -X main.date=$SOURCE_DATE_EPOCH \
-X main.builtBy=netbird-pkgs"

cmd="CGO_ENABLED=0 GOOS=linux GOARCH=$goarch GOTOOLCHAIN=local GOFLAGS=-mod=readonly \
$GO build -trimpath -buildvcs=false -buildmode=exe -tags load_wgnt_from_rsrc \
-ldflags \"$ldflags\" -o $outdir/netbird ./client"

if [ "$dry_run" -eq 1 ]; then
	printf '%s\n' "$cmd"
	exit 0
fi

mkdir -p "$outdir"
(
	cd "$source"
	CGO_ENABLED=0 GOOS=linux GOARCH=$goarch GOTOOLCHAIN=local GOFLAGS=-mod=readonly \
		"$GO" build -trimpath -buildvcs=false -buildmode=exe \
		-tags load_wgnt_from_rsrc -ldflags "$ldflags" \
		-o "$outdir/netbird" ./client
)

built=$("$outdir/netbird" version 2>&1 | head -n 1)
if [ "$built" != "$version" ]; then
	echo "built binary reports '$built', expected '$version'" >&2
	exit 1
fi
echo "built $outdir/netbird ($version)"
