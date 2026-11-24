#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015,SC2016
# Validate a candidate luci-app-netbird commit by building it for real.
#
# This is the signal for the one human gate in the pipeline: the package runs
# as root, so before a version bump PR is merged we want to know that the new
# upstream commit still applies our patches and still yields a working ipk.
#
# Always writes a markdown summary (success or failure); the exit status says
# whether the build passed.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: validate-luci-update.sh --sdk <dir> --workdir <dir> --summary <file>
         (--commit <sha> | --source <dir>) [--repo owner/name] [--sdk-version <v>]
         [--prepare-only]
EOF
	exit 2
}

sdk= workdir= summary= commit= source= repo=looong-cat/luci-app-netbird
prepare_only=0
while [ $# -gt 0 ]; do
	case "$1" in
		--sdk) sdk=$2; shift 2 ;;
		--workdir) workdir=$2; shift 2 ;;
		--summary) summary=$2; shift 2 ;;
		--commit) commit=$2; shift 2 ;;
		--source) source=$2; shift 2 ;;
		--repo) repo=$2; shift 2 ;;
		--sdk-version) sdk_version=$2; shift 2 ;;
		--prepare-only) prepare_only=1; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$workdir" ] && [ -n "$summary" ] || usage
[ "$prepare_only" -eq 1 ] || [ -n "$sdk" ] || usage
{ [ -n "$commit" ] || [ -n "$source" ]; } || usage
if [ "$prepare_only" -eq 0 ]; then
	[ -d "$sdk" ] || { echo "missing SDK dir: $sdk" >&2; exit 1; }
fi
[ -n "$commit" ] || commit="(local source)"

script_dir=$(cd "$(dirname "$0")" && pwd)

report() {
	# report <status> <detail>
	{
		printf '## LuCI build validation\n\n'
		printf '| | |\n|---|---|\n'
		printf '| upstream commit | `%s` |\n' "$commit"
		printf '| SDK | `%s` |\n' "${sdk_version:-unknown}"
		printf '| result | %s |\n\n' "$1"
		[ -z "$2" ] || printf '%s\n' "$2"
	} > "$summary"
	echo "wrote $summary ($1)"
}

fail() {
	report "**FAILED**" "$1"
	exit 1
}

rm -rf "$workdir"
mkdir -p "$workdir/src"

if [ -n "$source" ]; then
	[ -d "$source" ] || { echo "missing source dir: $source" >&2; exit 1; }
	cp -a "$source/." "$workdir/src/"
else
	# gh api writes the archive to stdout; it has no output flag.
	gh api "repos/${repo}/tarball/${commit}" > "$workdir/luci.tar.gz" \
		|| fail 'Could not download the upstream tarball.'
	tar -xzf "$workdir/luci.tar.gz" -C "$workdir" --strip-components=1 \
		|| fail 'Could not extract the upstream tarball.'
	# --strip-components=1 leaves the repo root; the package is nested inside.
	[ -d "$workdir/luci-app-netbird" ] \
		|| fail 'The upstream tarball has no `luci-app-netbird/` package directory.'
	cp -a "$workdir/luci-app-netbird/." "$workdir/src/"
fi

# The release job adds the upstream LICENSE and an upstream+ours NOTICE into the
# package before building, and verify-luci-ipk.sh requires both. Reproduce that
# here, or the candidate fails verification for reasons that are not upstream's.
upstream_root=$workdir
[ -n "$source" ] && upstream_root=$source
[ -f "$upstream_root/LICENSE" ] \
	|| fail "The candidate has no LICENSE at $upstream_root/LICENSE."
cp "$upstream_root/LICENSE" "$workdir/src/LICENSE"
: > "$workdir/src/NOTICE"
if [ -f "$upstream_root/NOTICE" ]; then
	cat "$upstream_root/NOTICE" >> "$workdir/src/NOTICE"
fi
extra_notice="$script_dir/../packaging/luci-app-netbird/NOTICE.tailscale-bsd3.txt"
[ -f "$extra_notice" ] \
	|| fail "Missing $extra_notice (needed to match the release package)."
cat "$extra_notice" >> "$workdir/src/NOTICE"

if [ "$prepare_only" -eq 1 ]; then
	report "**prepared** (no build requested)" "Assembled the candidate in \`$workdir/src\`."
	exit 0
fi

[ -f "$workdir/src/Makefile" ] || fail 'The package has no Makefile.'
pkg_version=$(sed -n 's/^PKG_VERSION:=//p' "$workdir/src/Makefile" | head -n 1)
pkg_release=$(sed -n 's/^PKG_RELEASE:=//p' "$workdir/src/Makefile" | head -n 1)
[ -n "$pkg_version" ] && [ -n "$pkg_release" ] \
	|| fail 'The Makefile does not pin PKG_VERSION/PKG_RELEASE.'

mkdir -p "$workdir/out"
if ! "$script_dir/build-luci-ipk.sh" --source "$workdir/src" --sdk "$sdk" \
	--version "$pkg_version" --release "$pkg_release" --outdir "$workdir/out" \
	> "$workdir/build.log" 2>&1; then
	tail -n 20 "$workdir/build.log" | sed 's/^/    /' > "$workdir/tail.txt"
	fail "The package did not build. Last lines:

\`\`\`
$(cat "$workdir/tail.txt")
\`\`\`"
fi

ipk="$workdir/out/luci-app-netbird_${pkg_version}-r${pkg_release}_all.ipk"
[ -f "$ipk" ] || fail "The build produced no ${pkg_version}-r${pkg_release} ipk."

# Verify against the version the build just produced, not our committed env:
# this commit is a candidate, our env still points at the old one.
printf 'LUCI_VERSION=%s\nLUCI_PKG_RELEASE=%s\n' "$pkg_version" "$pkg_release" \
	> "$workdir/candidate.env"
if ! "$script_dir/verify-luci-ipk.sh" --ipk "$ipk" --version-env "$workdir/candidate.env" \
	> "$workdir/verify.log" 2>&1; then
	fail "The built ipk failed verification:

\`\`\`
$(cat "$workdir/verify.log")
\`\`\`"
fi

report "**passed**" "Built and verified \`luci-app-netbird ${pkg_version}-r${pkg_release}\`:
patches applied, payload intact, \`binary_source 'opkg'\`, menu under VPN."
exit 0
