#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Verify a signed opkg feed tree before publishing.
set -eu
LC_ALL=C TZ=UTC; export LC_ALL TZ
usage() { echo "usage: verify-feed.sh --dir <feed> --pub <pubkey>" >&2; exit 2; }
dir= pub=
while [ $# -gt 0 ]; do case "$1" in --dir) dir=$2; shift 2;; --pub) pub=$2; shift 2;; *) usage;; esac; done
[ -n "$dir" ] && [ -n "$pub" ] || usage
[ -f "$dir/Packages" ] && [ -f "$dir/Packages.sig" ] || { echo "missing index or signature in $dir" >&2; exit 1; }
usign -V -m "$dir/Packages" -p "$pub"
while IFS= read -r line; do
	case "$line" in
		"Filename: "*) file=${line#Filename: } ;;
		"SHA256sum: "*) sha=${line#SHA256sum: } ;;
		"")
			if [ -n "${file:-}" ] && [ -n "${sha:-}" ]; then
				[ -f "$dir/$file" ] || { echo "missing $file" >&2; exit 1; }
				got=$(sha256sum "$dir/$file" | awk '{print $1}')
				[ "$got" = "$sha" ] || { echo "sha mismatch for $file" >&2; exit 1; }
			fi
			file= sha= ;;
	esac
done < "$dir/Packages"
echo "feed ok: $dir"
