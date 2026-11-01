#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/sign-feed.sh"
  TMP="$(mktemp -d)"
  FEED="$TMP/feed"
  mkdir -p "$FEED"
  printf 'Package: netbird\nVersion: 0.82.0-r1\nFilename: netbird_0.82.0-r1_aarch64_generic.ipk\n\n' > "$FEED/Packages"
  if ! command -v usign >/dev/null 2>&1; then
    skip "usign not installed"
  fi
  usign -G -s "$TMP/key.sec" -p "$TMP/key.pub" -c test >/dev/null 2>&1
}

teardown() { rm -rf "$TMP"; }

@test "signs Packages and self-verifies with the public key" {
  run "$SCRIPT" --dir "$FEED" --key "$TMP/key.sec" --pub "$TMP/key.pub"
  [ "$status" -eq 0 ]
  [ -f "$FEED/Packages.sig" ]
  run usign -V -m "$FEED/Packages" -p "$TMP/key.pub"
  [ "$status" -eq 0 ]
}

@test "verify mode rejects a tampered index" {
  "$SCRIPT" --dir "$FEED" --key "$TMP/key.sec" --pub "$TMP/key.pub" >/dev/null
  printf 'tampered\n' >> "$FEED/Packages"
  run "$SCRIPT" --dir "$FEED" --verify "$TMP/key.pub"
  [ "$status" -eq 1 ]
}

@test "fails when the secret key is missing" {
  run "$SCRIPT" --dir "$FEED" --key "$TMP/nope.sec"
  [ "$status" -eq 1 ]
}
