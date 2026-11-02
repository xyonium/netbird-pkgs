#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/update-luci-env.sh"
  TMP="$(mktemp -d)"
  ENVFILE="$TMP/luci.env"
  cat > "$ENVFILE" <<'ENV'
LUCI_VERSION=0.1.0
LUCI_COMMIT=cd812d93f8ca6c4563b716518c4308f9c448ac2f
LUCI_PKG_RELEASE=27
LUCI_SDK_VERSION=24.10.4
LUCI_SDK_SHA256=229e871f734a2cee5ce3ad6a3e98d3836b0899bfdeaea4d9c2c5cc7b1fce1407
LUCI_UPSTREAM_RELEASE=26
ENV
  cat > "$TMP/Makefile" <<'MK'
include $(TOPDIR)/rules.mk

LUCI_TITLE:=NetBird
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-netbird
PKG_VERSION:=0.2.0
PKG_RELEASE:=3
MK
}

teardown() { rm -rf "$TMP"; }

@test "keeps the pinned SDK fields when it updates the package version" {
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile"
  [ "$status" -eq 0 ]
  grep -qx 'LUCI_SDK_VERSION=24.10.4' "$ENVFILE"
  grep -qx 'LUCI_SDK_SHA256=229e871f734a2cee5ce3ad6a3e98d3836b0899bfdeaea4d9c2c5cc7b1fce1407' "$ENVFILE"
  grep -qx 'LUCI_VERSION=0.2.0' "$ENVFILE"
  grep -qx 'LUCI_COMMIT=1111111111111111111111111111111111111111' "$ENVFILE"
  grep -qx 'LUCI_UPSTREAM_RELEASE=3' "$ENVFILE"
}

@test "moves our release number forward instead of adopting upstream's" {
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile"
  [ "$status" -eq 0 ]
  # ours was 27, upstream says 3: never go backwards, and stay above upstream
  grep -qx 'LUCI_PKG_RELEASE=28' "$ENVFILE"
}

@test "is idempotent so a re-run does not drift the release number" {
  "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile" >/dev/null
  first=$(cat "$ENVFILE")
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile"
  [ "$status" -eq 0 ]
  [ "$(cat "$ENVFILE")" = "$first" ]
}

@test "reports whether the env actually changed" {
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHANGED=1"* ]]
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHANGED=0"* ]]
}

@test "fails when the Makefile does not pin PKG_VERSION and PKG_RELEASE" {
  printf 'include $(TOPDIR)/rules.mk\nPKG_NAME:=luci-app-netbird\n' > "$TMP/Makefile"
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/Makefile"
  [ "$status" -eq 1 ]
}

@test "fails on a missing Makefile" {
  run "$SCRIPT" --env-file "$ENVFILE" --commit 1111111111111111111111111111111111111111 \
    --makefile "$TMP/nope"
  [ "$status" -eq 1 ]
}

@test "requires every argument" {
  run "$SCRIPT" --env-file "$ENVFILE"
  [ "$status" -eq 2 ]
}
