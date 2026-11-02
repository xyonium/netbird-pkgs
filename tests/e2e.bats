#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  OUT="$BATS_TEST_TMPDIR/e2e"
}

@test "make e2e builds twice, verifies, signs and installs into a fake root" {
  E2E_OUT="$OUT" run make -C "$ROOT" e2e
  [ "$status" -eq 0 ]
  [ -f "$OUT/feed/Packages.sig" ]
  [ -f "$OUT/feed/Packages.gz" ]
  # The run must not leave anything behind in the repository tree.
  [ ! -e "$ROOT/dist/e2e" ]
}
