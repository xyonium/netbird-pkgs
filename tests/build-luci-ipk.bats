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

@test "applies the patch cleanly and leaves no backup or reject files" {
  run "$SCRIPT" --source "$SRC" --version 0.1.0 --release 26 \
    --outdir "$TMP/out" --patch-only
  [ "$status" -eq 0 ]
  [ ! -e "$SRC/root/etc/config/netbird_bin.orig" ]
  [ ! -e "$SRC/root/etc/config/netbird_bin.rej" ]
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
defconfig:
	@:
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

@test "keeps the SDK-built payload when adding licenses" {
  printf 'Apache-2.0\n' > "$SRC/LICENSE"
  printf 'NOTICE\n' > "$SRC/NOTICE"
  mkdir -p "$TMP/sdk/bin/packages/x86_64/base"
  cat > "$TMP/sdk/Makefile" <<'MK'
defconfig:
	@:
package/luci-app-netbird/compile:
	mkdir -p bin/packages/x86_64/base work/control work/data/etc/config work/data/htdocs/luci-static
	printf 'Package: luci-app-netbird\nVersion: 0.1.0-r26\nArchitecture: all\nDescription: x\n' > work/control/control
	echo x > work/data/etc/config/netbird_bin
	echo y > work/data/htdocs/luci-static/netbird.js
	tar -C work/control -czf work/control.tar.gz ./control
	tar -C work/data -czf work/data.tar.gz ./etc ./htdocs
	printf '2.0\n' > work/debian-binary
	tar -C work -czf bin/packages/x86_64/base/luci-app-netbird_0.1.0-r26_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
MK
  run "$SCRIPT" --source "$SRC" --sdk "$TMP/sdk" --version 0.1.0 --release 26 --outdir "$TMP/out"
  [ "$status" -eq 0 ]
  ipk="$TMP/out/luci-app-netbird_0.1.0-r26_all.ipk"
  run bash -c "tar -xOf '$ipk' ./data.tar.gz | tar -tzf -"
  [[ "$output" == *"etc/config/netbird_bin"* ]]
  [[ "$output" == *"htdocs/luci-static/netbird.js"* ]]
  run bash -c "tar -xOf '$ipk' ./control.tar.gz | tar -xzOf - ./control | grep -q '^Version: 0.1.0-r26$'"
  [ "$status" -eq 0 ]
}

@test "real SDK build when SDK_DIR and a real package source are provided" {
  # The synthetic fixture above is only enough to exercise patching and ipk
  # assembly; a real SDK will not index it, because it lacks the LuCI build
  # scaffolding (htdocs/, po/, the luci.mk package defines). Feeding it to a
  # real SDK would fail for reasons that say nothing about this script, so the
  # test needs a real upstream checkout: LUCI_SRC=/path/to/luci-app-netbird.
  #
  # Verified by hand against the pinned 24.10.4 SDK and upstream cd812d93:
  #   scripts/build-luci-ipk.sh --source <upstream> --sdk <sdk> \
  #     --version 0.1.0 --release 27 --outdir <out>
  # produced luci-app-netbird_0.1.0-r27_all.ipk whose payload had
  # binary_source 'opkg' and "admin/vpn/netbird", i.e. both patches applied.
  [ -n "${SDK_DIR:-}" ] || skip "SDK_DIR not set"
  [ -n "${LUCI_SRC:-}" ] || skip "LUCI_SRC not set (needs a real upstream checkout)"
  case "$LUCI_SRC" in
    */fixtures/*) skip "LUCI_SRC points at the synthetic fixture" ;;
  esac
  [ -f "$LUCI_SRC/Makefile" ] || skip "LUCI_SRC has no Makefile"
  [ -d "$LUCI_SRC/htdocs" ] || skip "LUCI_SRC is not a real LuCI package (no htdocs/)"
  mkdir -p "$TMP/real"
  cp -a "$LUCI_SRC/." "$TMP/real/"
  run "$SCRIPT" --source "$TMP/real" --sdk "$SDK_DIR" --version 0.1.0 --release 26 --outdir "$TMP/out"
  [ "$status" -eq 0 ]
  ipk="$TMP/out/luci-app-netbird_0.1.0-r26_all.ipk"
  [ -f "$ipk" ]
  run bash -c "tar -xOf '$ipk' ./data.tar.gz | tar -xzOf - ./etc/config/netbird_bin"
  [[ "$output" == *"option binary_source 'opkg'"* ]]
}

@test "applies every patch in the patch directory" {
  run "$SCRIPT" --source "$SRC" --version 0.1.0 --release 26 \
    --outdir "$TMP/out" --patch-only
  [ "$status" -eq 0 ]
  menu="$SRC/root/usr/share/luci/menu.d/luci-app-netbird.json"
  [ -f "$menu" ]
  # 0002 moves the app out of Services and into the VPN category.
  grep -q '"admin/vpn/netbird"' "$menu"
  ! grep -q '"admin/services/netbird' "$menu"
}

@test "stamps our release number over the upstream PKG_RELEASE" {
  grep -q '^PKG_RELEASE:=26$' "$SRC/Makefile"
  run "$SCRIPT" --source "$SRC" --version 0.1.0 --release 27 \
    --outdir "$TMP/out" --patch-only
  [ "$status" -eq 0 ]
  grep -q '^PKG_RELEASE:=27$' "$SRC/Makefile"
}
