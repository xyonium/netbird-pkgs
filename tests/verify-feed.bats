#!/usr/bin/env bats

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/verify-feed.sh"
  TMP="$(mktemp -d)"
  FEED="$TMP/feed"
  mkdir -p "$FEED"
  make_fixture_ipk "$FEED" netbird 0.82.0-r1 aarch64_generic
  "$BATS_TEST_DIRNAME/../scripts/make-feed.sh" --dir "$FEED" --arch aarch64_generic --retain 2 >/dev/null
  if ! command -v usign >/dev/null 2>&1; then skip "usign not installed"; fi
  usign -G -s "$TMP/key.sec" -p "$TMP/key.pub" -c test >/dev/null 2>&1
  "$BATS_TEST_DIRNAME/../scripts/sign-feed.sh" --dir "$FEED" --key "$TMP/key.sec" --pub "$TMP/key.pub" >/dev/null
}

teardown() { rm -rf "$TMP"; }

@test "accepts a signed feed whose files match the index" {
  run "$SCRIPT" --dir "$FEED" --pub "$TMP/key.pub"
  [ "$status" -eq 0 ]
}

@test "fails when an indexed file is missing or tampered" {
  printf 'x' >> "$FEED/netbird_0.82.0-r1_aarch64_generic.ipk"
  run "$SCRIPT" --dir "$FEED" --pub "$TMP/key.pub"
  [ "$status" -eq 1 ]
}
