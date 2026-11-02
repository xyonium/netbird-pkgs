#!/usr/bin/env bash
# Local end-to-end verification: build twice, verify, index, sign, install into a fake root.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ
export GOCACHE="${GOCACHE:-/tmp/gocache}"
export SOURCE_DATE_EPOCH=1700000000

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

CGO_ENABLED=0 go build -trimpath -o "$tmp/netbird" "$root/tests/fixtures/static.go"
printf 'BSD-3-Clause e2e fixture\n' > "$tmp/LICENSE"

for i in 1 2; do
	"$root/scripts/build-netbird-ipk.sh" --arch x86_64 --version 0.82.0 --pkg-release 1 \
		--binary "$tmp/netbird" --license "$tmp/LICENSE" \
		--source-date-epoch "$SOURCE_DATE_EPOCH" --outdir "$tmp/out$i" >/dev/null
done
cmp "$tmp/out1/netbird_0.82.0-r1_x86_64.ipk" "$tmp/out2/netbird_0.82.0-r1_x86_64.ipk"

"$root/scripts/verify-ipk.sh" --ipk "$tmp/out1/netbird_0.82.0-r1_x86_64.ipk" \
	--arch x86_64 --version 0.82.0 >/dev/null

mkdir -p "$tmp/feed"
cp "$tmp/out1/netbird_0.82.0-r1_x86_64.ipk" "$tmp/feed/"
"$root/scripts/make-feed.sh" --dir "$tmp/feed" --arch x86_64 --retain 2 >/dev/null

usign -G -s "$tmp/key.sec" -p "$tmp/key.pub" -c e2e >/dev/null 2>&1
"$root/scripts/sign-feed.sh" --dir "$tmp/feed" --key "$tmp/key.sec" --pub "$tmp/key.pub" >/dev/null
"$root/scripts/sign-feed.sh" --dir "$tmp/feed" --verify "$tmp/key.pub" >/dev/null

mkdir -p "$tmp/root"
"$root/scripts/install-feed.sh" --feed-url "file://$tmp/feed" --key-file "$tmp/key.pub" \
	--arch x86_64 --root "$tmp/root" --yes >/dev/null
grep -q '^src/gz netbird-pkgs ' "$tmp/root/etc/opkg/customfeeds.conf"

out=${E2E_OUT:-$root/dist/e2e}
mkdir -p "$out"
rm -rf "$out/feed"
cp -a "$tmp/feed" "$out/feed"
echo "e2e ok: $out/feed"
