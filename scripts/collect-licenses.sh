#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Collect third-party license texts from the Go module cache.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: collect-licenses.sh --mod-cache <dir> --out <file>
EOF
	exit 2
}

cache= out=
while [ $# -gt 0 ]; do
	case "$1" in
		--mod-cache) cache=$2; shift 2 ;;
		--out) out=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$cache" ] && [ -n "$out" ] || usage
[ -d "$cache" ] || { echo "missing module cache: $cache" >&2; exit 1; }

tmp="$out.tmp"
: > "$tmp"
rm -f "$tmp.missing"

find "$cache" -mindepth 1 -type d -name '*@*' ! -path '*/cache/download/*' | LC_ALL=C sort | while IFS= read -r dir; do
	lic=""
	for name in LICENSE LICENSE.md LICENSE.txt COPYING COPYING.md NOTICE; do
		if [ -f "$dir/$name" ]; then
			lic="$dir/$name"
			break
		fi
	done
	module=${dir#"$cache"/}
	if [ -n "$lic" ]; then
		{
			printf '===== %s =====\n' "$module"
			cat "$lic"
			printf '\n'
		} >> "$tmp"
	else
		printf 'MISSING LICENSE: %s\n' "$module" >> "$tmp.missing"
	fi
done

if [ -f "$tmp.missing" ]; then
	{
		printf '===== MISSING LICENSE (manual review) =====\n'
		cat "$tmp.missing"
	} >> "$tmp"
	rm -f "$tmp.missing"
fi

mv "$tmp" "$out"
