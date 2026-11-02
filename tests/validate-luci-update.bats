#!/usr/bin/env bats

# build-luci-ipk.sh needs a real SDK to compile, so these tests drive the
# failure paths and the reporting contract with a fake SDK whose `make` is a
# no-op. The happy path is covered by the CI job that runs this for real.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-luci-update.sh"
  TMP="$(mktemp -d)"
  SRC="$TMP/pkgsrc"
  mkdir -p "$SRC/root/etc/config" "$SRC/root/usr/share/luci/menu.d"
  cat > "$SRC/Makefile" <<'MK'
include $(TOPDIR)/rules.mk
PKG_NAME:=luci-app-netbird
PKG_VERSION:=0.1.0
PKG_RELEASE:=26
MK
  # Real upstream shapes: the patches are generated against these, so a
  # synthetic stub would fail to apply and never reach the verification step.
  cp "$BATS_TEST_DIRNAME/fixtures/patchsrc/root/etc/config/netbird_bin" \
    "$SRC/root/etc/config/netbird_bin"
  cp "$BATS_TEST_DIRNAME/fixtures/patchsrc/root/usr/share/luci/menu.d/luci-app-netbird.json" \
    "$SRC/root/usr/share/luci/menu.d/luci-app-netbird.json"
  printf 'Apache-2.0\n' > "$SRC/LICENSE"
  printf 'NOTICE\n' > "$SRC/NOTICE"
  # A fake SDK: `make ... compile` produces the ipk the script looks for.
  mkdir -p "$TMP/sdk"
  cat > "$TMP/sdk/Makefile" <<'MK'
defconfig:
	@:

package/luci-app-netbird/compile:
	@mkdir -p work/control work/data/etc work/data/usr/share/doc/luci-app-netbird
	printf 'Package: luci-app-netbird\nVersion: 0.1.0-r26\nArchitecture: all\nDescription: x\n' > work/control/control
	printf 'config x\n' > work/data/etc/netbird_bin
	printf 'L\n' > work/data/usr/share/doc/luci-app-netbird/LICENSE
	printf 'N\n' > work/data/usr/share/doc/luci-app-netbird/NOTICE
	tar -C work/control -czf work/control.tar.gz ./control
	tar -C work/data -czf work/data.tar.gz ./etc ./usr
	printf '2.0\n' > work/debian-binary
	mkdir -p bin/packages/x86_64/base
	tar -C work -czf bin/packages/x86_64/base/luci-app-netbird_0.1.0-r26_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
MK
}

teardown() { rm -rf "$TMP"; }

@test "writes a failure summary when the source has no Makefile" {
  rm -f "$SRC/Makefile"
  run "$SCRIPT" --sdk "$TMP/sdk" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ "$status" -eq 1 ]
  [ -f "$TMP/s.md" ]
  grep -q 'FAILED' "$TMP/s.md"
  grep -q 'Makefile' "$TMP/s.md"
}

@test "writes a failure summary when the Makefile does not pin a version" {
  printf 'PKG_NAME:=luci-app-netbird\n' > "$SRC/Makefile"
  run "$SCRIPT" --sdk "$TMP/sdk" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ "$status" -eq 1 ]
  grep -q 'PKG_VERSION' "$TMP/s.md"
}

@test "writes a failure summary that explains the build failure" {
  # Remove the patch target so build-luci-ipk.sh refuses to run.
  rm -f "$SRC/root/etc/config/netbird_bin"
  run "$SCRIPT" --sdk "$TMP/sdk" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ "$status" -eq 1 ]
  grep -q 'FAILED' "$TMP/s.md"
  grep -q 'netbird_bin' "$TMP/s.md"
}

@test "fails when the SDK directory is missing" {
  run "$SCRIPT" --sdk "$TMP/nope" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ "$status" -eq 1 ]
}

@test "requires a commit or a source directory" {
  run "$SCRIPT" --sdk "$TMP/sdk" --workdir "$TMP/w" --summary "$TMP/s.md"
  [ "$status" -eq 2 ]
}

@test "always writes a summary that names the upstream commit" {
  run "$SCRIPT" --sdk "$TMP/sdk" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ -f "$TMP/s.md" ]
  grep -q 'upstream commit' "$TMP/s.md"
}

@test "rejects a build whose payload would not pass verification" {
  # The fake SDK emits an ipk without the VPN menu and without the opkg
  # default, which is exactly what an upstream regression would look like.
  run "$SCRIPT" --sdk "$TMP/sdk" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ "$status" -eq 1 ]
  grep -q 'failed verification' "$TMP/s.md"
  grep -q 'netbird_bin' "$TMP/s.md"
}

@test "reports success when the built ipk passes every check" {
  # A fake SDK that packages the patched source, so the whole chain
  # (patch -> build -> verify) succeeds end to end.
  mkdir -p "$TMP/good"
  cat > "$TMP/good/Makefile" <<'MK'
defconfig:
	@:

package/luci-app-netbird/compile:
	@mkdir -p work/control work/data
	printf 'Package: luci-app-netbird\nVersion: 0.1.0-r26\nArchitecture: all\nDescription: x\n' > work/control/control
	cp -a package/luci-app-netbird/root/. work/data/
	mkdir -p work/data/usr/share/doc/luci-app-netbird
	printf 'L\n' > work/data/usr/share/doc/luci-app-netbird/LICENSE
	printf 'N\n' > work/data/usr/share/doc/luci-app-netbird/NOTICE
	tar -C work/control -czf work/control.tar.gz ./control
	tar -C work/data -czf work/data.tar.gz ./etc ./usr
	printf '2.0\n' > work/debian-binary
	mkdir -p bin/packages/x86_64/base
	tar -C work -czf bin/packages/x86_64/base/luci-app-netbird_0.1.0-r26_all.ipk ./debian-binary ./data.tar.gz ./control.tar.gz
MK
  run "$SCRIPT" --sdk "$TMP/good" --workdir "$TMP/w" --summary "$TMP/s.md" --source "$SRC"
  [ "$status" -eq 0 ]
  grep -q 'passed' "$TMP/s.md"
  grep -q '0.1.0-r26' "$TMP/s.md"
}
