#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
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
         (--commit <sha> | --source <dir>) [--repo owner/name]
EOF
	exit 2
}

sdk= workdir= summary= commit= source= repo=looong-cat/luci-app-netbird
while [ $# -gt 0 ]; do
	case "$1" in
		--sdk) sdk=$2; shift 2 ;;
		--workdir) workdir=$2; shift 2 ;;
		--summary) summary=$2; shift 2 ;;
		--commit) commit=$2; shift 2 ;;
		--source) source=$2; shift 2 ;;
		--repo) repo=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$sdk" ] && [ -n "$workdir" ] && [ -n "$summary" ] || usage
{ [ -n "$commit" ] || [ -n "$source" ]; } || usage
[ -d "$sdk" ] || { echo "missing SDK dir: $sdk" >&2; exit 1; }
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
