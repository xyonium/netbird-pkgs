#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Add LICENSE/NOTICE documents to an already built LuCI ipk.
set -eu
LC_ALL=C TZ=UTC; export LC_ALL TZ
usage() { echo "usage: augment-luci-ipk.sh --ipk <path> --license <file> --notice <file> [--extra-notice <file>]" >&2; exit 2; }
ipk= license= notice= extra=
while [ $# -gt 0 ]; do case "$1" in
	--ipk) ipk=$2; shift 2;; --license) license=$2; shift 2;;
	--notice) notice=$2; shift 2;; --extra-notice) extra=$2; shift 2;;
	*) usage;; esac; done
[ -f "$ipk" ] && [ -f "$license" ] && [ -f "$notice" ] || usage
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM
tar -xzf "$ipk" -C "$work"
# An ipk is a container of tarballs: unpack the payload before adding files,
# otherwise the rewrapped data.tar.gz would contain the documents alone.
mkdir -p "$work/data"
tar -xzf "$work/data.tar.gz" -C "$work/data"
mkdir -p "$work/data/usr/share/doc/luci-app-netbird"
cp "$license" "$work/data/usr/share/doc/luci-app-netbird/LICENSE"
cp "$notice" "$work/data/usr/share/doc/luci-app-netbird/NOTICE"
[ -z "$extra" ] || cat "$extra" >> "$work/data/usr/share/doc/luci-app-netbird/NOTICE"
epoch=${SOURCE_DATE_EPOCH:-0}
opts="--sort=name --mtime=@$epoch --owner=0 --group=0 --numeric-owner"
entries=$(cd "$work/data" && find . -mindepth 1 -maxdepth 1)
# shellcheck disable=SC2086
tar -C "$work/data" $opts -cf - $entries | gzip -9n > "$work/data.tar.gz"
# shellcheck disable=SC2086
tar -C "$work" $opts -cf - ./debian-binary ./data.tar.gz ./control.tar.gz | gzip -9n > "$ipk"
echo "augmented $ipk"
