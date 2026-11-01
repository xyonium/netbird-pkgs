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

@test "packages LICENSE and NOTICE into the built ipk" {
  printf 'Apache-2.0\n' > "$SRC/LICENSE"
  printf 'NOTICE\n' > "$SRC/NOTICE"
  mkdir -p "$TMP/sdk/bin/packages/x86_64/base"
  cat > "$TMP/sdk/Makefile" <<'MK'
package/luci-app-netbird/compile:
	mkdir -p bin/packages/x86_64/base work/control work/data/etc/config
	printf 'Package: luci-app-netbird\nVersion: 0.1.0-r26\nArchitecture: all\nDescription: x\n' > work/control/control
	echo x > work/data/etc/config/netbird
	tar -C work/control -czf work/control.tar.gz ./control
	tar -C work/data -czf work/data.tar.gz ./etc
	printf '2.0\n' > work/debian-binary
	tar -C work -czf bin/packages/x86_64/base/luci-app-netbird_0.1.0-r26_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
MK
  run "$SCRIPT" --source "$SRC" --sdk "$TMP/sdk" --version 0.1.0 --release 26 --outdir "$TMP/out"
  [ "$status" -eq 0 ]
  local ipk="$TMP/out/luci-app-netbird_0.1.0-r26_all.ipk"
  [ -f "$ipk" ]
  run bash -c "tar -xOf '$ipk' ./data.tar.gz | tar -tzf - | grep -q 'doc/luci-app-netbird/LICENSE'"
  [ "$status" -eq 0 ]
  run bash -c "tar -xOf '$ipk' ./data.tar.gz | tar -tzf - | grep -q 'doc/luci-app-netbird/NOTICE'"
  [ "$status" -eq 0 ]
}

@test "real SDK build when SDK_DIR is provided" {
  [ -n "${SDK_DIR:-}" ] || skip "SDK_DIR not set"
  run "$SCRIPT" --source "$SRC" --sdk "$SDK_DIR" --version 0.1.0 --release 26 --outdir "$TMP/out"
  [ "$status" -eq 0 ]
  ls "$TMP/out"/luci-app-netbird_*_all.ipk
}
