#!/bin/sh
# Configure an OpenWrt device to use the netbird-pkgs feed.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: install-feed.sh --feed-url <url> [--key-url <url> | --key-file <path>] \
         [--arch auto|aarch64_generic|x86_64] [--root <dir>] [--yes]
EOF
	exit 2
}

feed_url= key_url= key_file= arch=auto root=/ yes=0
while [ $# -gt 0 ]; do
	case "$1" in
		--feed-url) feed_url=$2; shift 2 ;;
		--key-url) key_url=$2; shift 2 ;;
		--key-file) key_file=$2; shift 2 ;;
		--arch) arch=$2; shift 2 ;;
		--root) root=$2; shift 2 ;;
		--yes) yes=1; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$feed_url" ] || usage
case "$feed_url" in
	http://*|https://*|file://*) ;;
	*) echo "unsupported feed URL: $feed_url" >&2; exit 2 ;;
esac

root=${root%/}
[ -n "$root" ] || root=/

if [ "$arch" = auto ]; then
	arch=$(opkg print-architecture 2>/dev/null \
		| awk '$1=="arch" && ($2=="aarch64_generic" || $2=="x86_64"){print $3, $2}' \
		| sort -rn | awk 'NR==1{print $2}')
fi
case "$arch" in
	aarch64_generic|x86_64) ;;
	*) echo "cannot determine a supported arch (use --arch): ${arch:-none}" >&2; exit 1 ;;
esac

tmp=""
cleanup() { [ -z "$tmp" ] || rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

if [ -n "$key_url" ] && [ -z "$key_file" ]; then
	tmp=$(mktemp -d)
	key_file="$tmp/feed.pub"
	case "$key_url" in
		file://*) cp "${key_url#file://}" "$key_file" ;;
		*) wget -q -O "$key_file" "$key_url" ;;
	esac
fi

fp=""
if [ -n "$key_file" ]; then
	[ -f "$key_file" ] || { echo "missing key: $key_file" >&2; exit 1; }
	command -v usign >/dev/null 2>&1 || { echo "usign not installed" >&2; exit 1; }
	fp=$(usign -F -p "$key_file")
fi

conf="$root/etc/opkg/customfeeds.conf"
line="src/gz netbird-pkgs $feed_url/$arch"

if [ "$yes" -ne 1 ]; then
	echo "planned changes (re-run with --yes to apply):" >&2
	[ -z "$fp" ] || echo "  install key $key_file -> $root/etc/opkg/keys/$fp" >&2
	echo "  append to $conf: $line" >&2
	exit 1
fi

mkdir -p "$root/etc/opkg/keys"
if [ -n "$fp" ]; then
	cp "$key_file" "$root/etc/opkg/keys/$fp"
	chmod 0644 "$root/etc/opkg/keys/$fp"
fi
touch "$conf"
grep -q "^$line\$" "$conf" || printf '%s\n' "$line" >> "$conf"
echo "feed configured: $line"
