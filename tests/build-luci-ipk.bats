#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/build-luci-ipk.sh"
  TMP="$(mktemp -d)"
  SRC="$TMP/src"
  mkdir -p "$SRC"
  cp -a "$BATS_TEST_DIRNAME/fixtures/patchsrc/." "$SRC/"
}

teardown() { rm -rf "$TMP"; }

@test "patch-only changes binary_source default to opkg" {
  run "$SCRIPT" --source "$SRC" --version 0.1.0 --release 26 \
    --outdir "$TMP/out" --patch-only
  [ "$status" -eq 0 ]
  grep -q "option binary_source 'opkg'" "$SRC/root/etc/config/netbird_bin"
}

@test "refuses to apply an already applied patch" {
  "$SCRIPT" --source "$SRC" --version 0.1.0 --release 26 \
    --outdir "$TMP/out" --patch-only >/dev/null
  run "$SCRIPT" --source "$SRC" --version 0.1.0 --release 26 \
    --outdir "$TMP/out" --patch-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"already"* || "$output" == *"fail"* ]]
}

@test "requires source and version" {
  run "$SCRIPT" --outdir "$TMP/out"
  [ "$status" -eq 2 ]
}

@test "real SDK build when SDK_DIR is provided" {
  [ -n "${SDK_DIR:-}" ] || skip "SDK_DIR not set"
  run "$SCRIPT" --source "$SRC" --sdk "$SDK_DIR" --version 0.1.0 --release 26 --outdir "$TMP/out"
  [ "$status" -eq 0 ]
  ls "$TMP/out"/luci-app-netbird_*_all.ipk
}
