#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Download the ipks of recent releases so the rebuilt feed keeps a rollback path.
#
# The published feed is the documented downgrade route, so a failed download
# must fail the publish job rather than quietly drop the previous versions.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: fetch-previous-ipks.sh --dir <dir> [--limit N] [--exclude <tag>]
EOF
	exit 2
}

dir= limit=3 exclude=
while [ $# -gt 0 ]; do
	case "$1" in
		--dir) dir=$2; shift 2 ;;
		--limit) limit=$2; shift 2 ;;
		--exclude) exclude=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$dir" ] || usage
case "$limit" in
	*[!0-9]*|'') echo "invalid limit: $limit" >&2; exit 2 ;;
esac
mkdir -p "$dir"

tags=$(gh release list --limit "$limit" --json tagName --jq '.[].tagName')
for tag in $tags; do
	[ -z "$exclude" ] || [ "$tag" != "$exclude" ] || continue
	assets=$(gh release view "$tag" --json assets --jq '.assets[].name' || exit 1)
	ipks=$(printf '%s\n' "$assets" | grep '\.ipk$' || :)
	if [ -z "$ipks" ]; then
		echo "skipping $tag: no ipk assets" >&2
		continue
	fi
	gh release download "$tag" --pattern '*.ipk' --dir "$dir" --clobber \
		|| { echo "failed to download ipks from $tag" >&2; exit 1; }
	echo "fetched $(printf '%s\n' "$ipks" | grep -c '\.ipk$') ipk(s) from $tag"
done
