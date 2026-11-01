#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  rm -rf "$ROOT/dist/e2e"
}

teardown() {
  rm -rf "$ROOT/dist/e2e"
}

@test "make e2e builds twice, verifies, signs and installs into a fake root" {
  run make -C "$ROOT" e2e
  [ "$status" -eq 0 ]
  [ -f "$ROOT/dist/e2e/feed/Packages.sig" ]
  [ -f "$ROOT/dist/e2e/feed/Packages.gz" ]
}
