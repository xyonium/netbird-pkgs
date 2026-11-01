#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Build a deterministic opkg Packages index from ipk files.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: make-feed.sh --dir <feed> --arch <arch> [--retain N] [--ipk <path>]...
EOF
	exit 2
}

dir= arch= retain=2
ipks=
while [ $# -gt 0 ]; do
	case "$1" in
		--dir) dir=$2; shift 2 ;;
		--arch) arch=$2; shift 2 ;;
		--retain) retain=$2; shift 2 ;;
		--ipk) ipks="$ipks $2"; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$dir" ] && [ -n "$arch" ] || usage
case "$retain" in
	*[!0-9]*|'') echo "invalid retain: $retain" >&2; exit 2 ;;
esac
mkdir -p "$dir"

for f in $ipks; do
	[ -f "$f" ] || { echo "missing ipk: $f" >&2; exit 1; }
	[ "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" = "$(cd "$dir" && pwd)/$(basename "$f")" ] \
		|| cp "$f" "$dir/"
done

rm -f "$dir/Packages.sig"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM

extract_control() {
	tar -xOf "$1" ./control.tar.gz | tar -xzOf - ./control
}

records="$work/records"
: > "$records"

for ipk in "$dir"/*.ipk; do
	[ -f "$ipk" ] || continue
	control=$(extract_control "$ipk")
	pkg=$(printf '%s\n' "$control" | sed -n 's/^Package: //p' | head -n 1)
	ver=$(printf '%s\n' "$control" | sed -n 's/^Version: //p' | head -n 1)
	parm=$(printf '%s\n' "$control" | sed -n 's/^Architecture: //p' | head -n 1)
	[ -n "$pkg" ] && [ -n "$ver" ] || { echo "invalid ipk: $ipk" >&2; exit 1; }
	if [ "$parm" != "$arch" ] && [ "$parm" != all ]; then
		echo "unexpected architecture '$parm' in $ipk (feed $arch)" >&2
		exit 1
	fi
	upstream=${ver%-r*}
	release=${ver##*-r}
	printf '%s|%s|%s|%s\n' "$pkg" "$upstream" "$release" "$(basename "$ipk")" >> "$records"
done

selected="$work/selected"
: > "$selected"
for pkg in $(cut -d'|' -f1 "$records" | sort -u); do
	versions=$(awk -F'|' -v p="$pkg" '$1==p{print $2}' "$records" | sort -Vu | tail -n "$retain")
	for uv in $versions; do
		awk -F'|' -v p="$pkg" -v v="$uv" '$1==p && $2==v' "$records" \
			| sort -t'|' -k3,3n | tail -n 1 >> "$selected"
	done
done
sort -t'|' -k1,1 -k2,2V "$selected" > "$selected.sorted"

: > "$dir/Packages"
while IFS='|' read -r pkg uv release file; do
	[ -n "$file" ] || continue
	control=$(extract_control "$dir/$file")
	size=$(wc -c < "$dir/$file")
	sha=$(sha256sum "$dir/$file" | awk '{print $1}')
	{
		printf '%s\n' "$control" | awk -v fname="$file" -v size="$size" -v sha="$sha" '
			/^Package: /{pkg=$0}
			/^Version: /{ver=$0}
			/^Depends: /{dep=$0}
			/^Section: /{sec=$0}
			/^Category: /{cat=$0}
			/^Architecture: /{arch=$0}
			/^Installed-Size: /{isize=$0}
			/^License: /{lic=$0}
			/^Description: /{desc=$0; next}
			indesc && /^ /{desc=desc "\n" $0; next}
			{indesc=0}
			END{
				print pkg; print ver; if (dep!="") print dep
				if (sec!="") print sec; if (cat!="") print cat
				print arch; if (isize!="") print isize
				if (lic!="") print lic
				print "Filename: " fname
				print "Size: " size
				print "SHA256sum: " sha
				if (desc!="") print desc
			}'
		printf '\n'
	} >> "$dir/Packages"
done < "$selected.sorted"

gzip -9n -c "$dir/Packages" > "$dir/Packages.gz"
rm -f "$selected" "$selected.sorted"
