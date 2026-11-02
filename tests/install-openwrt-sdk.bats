#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/install-openwrt-sdk.sh"
  TMP="$(mktemp -d)"
  SHA=229e871f734a2cee5ce3ad6a3e98d3836b0899bfdeaea4d9c2c5cc7b1fce1407
  if ! command -v zstd >/dev/null 2>&1; then
    # The real SDK ships as .tar.zst; without zstd only the argument and
    # checksum paths can be exercised.
    SKIP_ZSTD=1
    return 0
  fi
  # A minimal tarball that looks like an SDK tree: it must contain scripts/feeds.
  mkdir -p "$TMP/tree/openwrt-sdk/scripts"
  cat > "$TMP/tree/openwrt-sdk/scripts/feeds" <<'FEEDS'
#!/bin/sh
exit 0
FEEDS
  chmod +x "$TMP/tree/openwrt-sdk/scripts/feeds"
  ( cd "$TMP/tree" && tar --zstd -cf "$TMP/sdk.tar.zst" ./openwrt-sdk )
  SHA=$(sha256sum "$TMP/sdk.tar.zst" | awk '{print $1}')
}

teardown() { rm -rf "$TMP"; }

@test "installs a verified SDK tarball and reports it ready" {
  [ -z "${SKIP_ZSTD:-}" ] || skip "zstd not installed"
  run "$SCRIPT" --version 24.10.4 --sha256 "$SHA" --dest "$TMP/dest" --tarball "$TMP/sdk.tar.zst"
  [ "$status" -eq 0 ]
  [ -x "$TMP/dest/scripts/feeds" ]
  [[ "$output" == *"sdk ready"* ]]
}

@test "rejects a checksum mismatch instead of installing" {
  [ -z "${SKIP_ZSTD:-}" ] || skip "zstd not installed"
  run "$SCRIPT" --version 24.10.4 --sha256 "$(printf 'a%.0s' $(seq 64))" \
    --dest "$TMP/dest" --tarball "$TMP/sdk.tar.zst"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checksum mismatch"* ]]
  [ ! -d "$TMP/dest" ]
}

@test "rejects a tree that is not an SDK" {
  [ -z "${SKIP_ZSTD:-}" ] || skip "zstd not installed"
  mkdir -p "$TMP/empty/notasdk" && printf 'x\n' > "$TMP/empty/notasdk/f"
  ( cd "$TMP/empty" && tar --zstd -cf "$TMP/bad.tar.zst" ./notasdk )
  bad=$(sha256sum "$TMP/bad.tar.zst" | awk '{print $1}')
  run "$SCRIPT" --version 24.10.4 --sha256 "$bad" --dest "$TMP/dest" --tarball "$TMP/bad.tar.zst"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an SDK tree"* ]]
}

@test "validates the sha256 before touching the network" {
  run "$SCRIPT" --version 24.10.4 --sha256 not-a-hash --dest "$TMP/dest"
  [ "$status" -eq 2 ]
}

@test "requires version, sha256 and dest" {
  run "$SCRIPT" --version 24.10.4
  [ "$status" -eq 2 ]
}
