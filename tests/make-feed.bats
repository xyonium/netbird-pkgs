#!/usr/bin/env bats

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/make-feed.sh"
  TMP="$(mktemp -d)"
  FEED="$TMP/feed"
  mkdir -p "$FEED"
  make_fixture_ipk "$FEED" netbird 0.82.0-r1 aarch64_generic
  make_fixture_ipk "$FEED" netbird 0.81.4-r1 aarch64_generic
  make_fixture_ipk "$FEED" netbird 0.80.0-r1 aarch64_generic
  make_fixture_ipk "$FEED" luci-app-netbird 0.1.0-r26 all
}

teardown() { rm -rf "$TMP"; }

@test "writes a sorted index with hashes and relative filenames" {
  run "$SCRIPT" --dir "$FEED" --arch aarch64_generic --retain 2
  [ "$status" -eq 0 ]
  [ -f "$FEED/Packages" ]
  run gzip -dc "$FEED/Packages.gz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Package: netbird"* ]]
  [[ "$output" == *"Filename: netbird_0.82.0-r1_aarch64_generic.ipk"* ]]
  [[ "$output" == *"SHA256sum: $(sha256sum "$FEED/netbird_0.82.0-r1_aarch64_generic.ipk" | awk '{print $1}')"* ]]
  [[ "$output" == *"Filename: luci-app-netbird_0.1.0-r26_all.ipk"* ]]
  [[ "$output" != *"netbird_0.80.0-r1"* ]]
  [ "$(grep -c '^Package: netbird$' "$FEED/Packages")" -eq 2 ]
}

@test "rejects a missing explicit ipk" {
  run "$SCRIPT" --dir "$FEED" --arch aarch64_generic --ipk "$TMP/nope.ipk"
  [ "$status" -eq 1 ]
}

@test "fails when an ipk has an unexpected architecture for the feed" {
  make_fixture_ipk "$FEED" netbird 0.82.0-r1 aarch64_cortex-a53
  run "$SCRIPT" --dir "$FEED" --arch aarch64_generic
  [ "$status" -eq 1 ]
}

@test "keeps multi-line Description blocks from the control file" {
  run "$SCRIPT" --dir "$FEED" --arch aarch64_generic --retain 2
  [ "$status" -eq 0 ]
  run grep -A1 '^Description:' "$FEED/Packages"
  [[ "$output" == *"Package2:"* || "$output" == *"Description: fixture"* ]]
}

@test "removes a stale Packages.sig when rebuilding the index" {
  printf 'stale' > "$FEED/Packages.sig"
  run "$SCRIPT" --dir "$FEED" --arch aarch64_generic --retain 2
  [ "$status" -eq 0 ]
  [ ! -f "$FEED/Packages.sig" ]
}

@test "empty feed yields an empty index" {
  run "$SCRIPT" --dir "$TMP/empty" --arch x86_64
  [ "$status" -eq 0 ]
  [ -f "$TMP/empty/Packages" ]
  [ ! -s "$TMP/empty/Packages" ]
}
