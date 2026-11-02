#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Install the tools `make lint test` needs on a Debian/Ubuntu runner.
#
# Every workflow that runs the test suite calls this, so the luci-watch job
# gets usign too: tests/e2e.sh signs a feed, and without usign the whole suite
# fails and the watch job never reaches its PR step.
set -eu

prefix=${PREFIX:-/usr/local/bin}
# Pinned so a force-push or a broken master cannot change what CI installs.
USIGN_COMMIT=c4c72b1b07945ee192361dc751291a7c98d6adcd

sudo apt-get update
sudo apt-get install -y bats shellcheck cmake build-essential zstd

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
git init -q "$work/usign"
git -C "$work/usign" remote add origin https://github.com/openwrt/usign
git -C "$work/usign" fetch -q --depth 1 origin "$USIGN_COMMIT"
git -C "$work/usign" checkout -q FETCH_HEAD
cmake -S "$work/usign" -B "$work/usign/build" >/dev/null
make -C "$work/usign/build" >/dev/null
sudo install -m0755 "$work/usign/build/usign" "$prefix/usign"

command -v go >/dev/null 2>&1 || {
	echo "go is required: the bats fixtures build Go binaries (e2e, verify-ipk)" >&2
	exit 1
}
echo "test dependencies ready: bats, shellcheck, usign, zstd, go"
