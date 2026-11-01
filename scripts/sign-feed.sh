#!/bin/sh
# Sign or verify the opkg Packages index with usign.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: sign-feed.sh --dir <feed> --key <secret> [--pub <pubkey>]
       sign-feed.sh --dir <feed> --verify <pubkey>
EOF
	exit 2
}

dir= key= pub= verify=
while [ $# -gt 0 ]; do
	case "$1" in
		--dir) dir=$2; shift 2 ;;
		--key) key=$2; shift 2 ;;
		--pub) pub=$2; shift 2 ;;
		--verify) verify=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$dir" ] && [ -f "$dir/Packages" ] || { echo "missing $dir/Packages" >&2; exit 1; }
command -v usign >/dev/null 2>&1 || { echo "usign not installed" >&2; exit 1; }

if [ -n "$verify" ]; then
	usign -V -m "$dir/Packages" -p "$verify"
	exit $?
fi

[ -n "$key" ] && [ -f "$key" ] || { echo "missing secret key: $key" >&2; exit 1; }
usign -S -m "$dir/Packages" -s "$key"
[ -f "$dir/Packages.sig" ] || { echo "signature not created" >&2; exit 1; }

if [ -n "$pub" ]; then
	usign -V -m "$dir/Packages" -p "$pub"
fi
echo "signed $dir/Packages"
