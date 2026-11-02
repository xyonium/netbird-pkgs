#!/usr/bin/env bats

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/make-istore.sh"
  TMP="$(mktemp -d)"
  IN="$TMP/in"
  OUT="$TMP/out"
  mkdir -p "$IN"
  make_fixture_ipk "$IN" netbird 0.82.0-r1 aarch64_generic
  make_fixture_ipk "$IN" netbird 0.82.0-r1 x86_64
  make_fixture_ipk "$IN" luci-app-netbird 0.1.0-r26 all
  make_fixture_ipk "$IN" luci-i18n-netbird-zh-cn 0.1.0-r26 all
  sha_before="$(sha256sum "$IN/netbird_0.82.0-r1_aarch64_generic.ipk" | awk '{print $1}')"
}

teardown() { rm -rf "$TMP"; }

@test "produces the iStore bundle layout and metadata" {
  run "$SCRIPT" --ipk-dir "$IN" --outdir "$OUT" --version 0.82.0 --pkg-release 1
  [ "$status" -eq 0 ]
  [ -f "$OUT/bin/packages/aarch64_cortex-a53/nas/netbird_0.82.0-r1_aarch64_cortex-a53.ipk" ]
  [ -f "$OUT/bin/packages/x86_64/nas/netbird_0.82.0-r1_x86_64.ipk" ]
  [ -f "$OUT/bin/packages/all/nas_luci/luci-app-netbird_0.1.0-r26_all.ipk" ]
  [ -f "$OUT/bin/packages/all/nas_luci/luci-i18n-netbird-zh-cn_0.1.0-r26_all.ipk" ]
  [ -f "$OUT/applications/app-meta-netbird/Makefile" ]
  [ -f "$OUT/applications/app-meta-netbird/logo.png" ]
}

@test "repackages only the Architecture field and keeps the source intact" {
  run "$SCRIPT" --ipk-dir "$IN" --outdir "$OUT" --version 0.82.0 --pkg-release 1
  [ "$status" -eq 0 ]
  local control
  control="$(tar -xOf "$OUT/bin/packages/aarch64_cortex-a53/nas/netbird_0.82.0-r1_aarch64_cortex-a53.ipk" ./control.tar.gz | tar -xzOf - ./control)"
  [[ "$control" == *"Architecture: aarch64_cortex-a53"* ]]
  [[ "$control" == *"Package: netbird"* ]]
  [ "$sha_before" = "$(sha256sum "$IN/netbird_0.82.0-r1_aarch64_generic.ipk" | awk '{print $1}')" ]
}

@test "renders the metadata Makefile with the release values" {
  run "$SCRIPT" --ipk-dir "$IN" --outdir "$OUT" --version 0.82.0 --pkg-release 1
  [ "$status" -eq 0 ]
  run cat "$OUT/applications/app-meta-netbird/Makefile"
  [[ "$output" == *"PKG_VERSION:=0.82.0"* ]]
  [[ "$output" == *"PKG_RELEASE:=1"* ]]
  [[ "$output" == *"META_DEPENDS:=+netbird +luci-app-netbird"* ]]
  [[ "$output" == *"META_LUCI_ENTRY:=/cgi-bin/luci/admin/services/netbird"* ]]
  [ "$(stat -c %s "$OUT/applications/app-meta-netbird/logo.png")" -le 51200 ]
}

@test "fails when an expected ipk is missing" {
  rm -f "$IN/netbird_0.82.0-r1_x86_64.ipk"
  run "$SCRIPT" --ipk-dir "$IN" --outdir "$OUT" --version 0.82.0 --pkg-release 1
  [ "$status" -eq 1 ]
}

@test "keeps the metadata template under a name an OpenWrt feed scan ignores" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # scripts/feeds walks every Makefile in a feed; a template with @PLACEHOLDER@
  # fields and a missing include makes the whole feed index fail to build.
  [ ! -f "$repo/packaging/istore/app-meta-netbird/Makefile" ]
  [ -f "$repo/packaging/istore/app-meta-netbird/Makefile.in" ]
}

@test "ships a real, square icon instead of a blank placeholder" {
  repo="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  logo="$repo/packaging/istore/app-meta-netbird/logo.png"
  [ -f "$logo" ]
  size=$(stat -c %s "$logo")
  [ "$size" -le 51200 ]
  # A single flat colour compresses to a few hundred bytes; a real icon does not.
  [ "$size" -gt 1024 ]
  run file "$logo"
  [[ "$output" == *"PNG image data"* ]]
  dims=$(printf '%s' "$output" | sed -n 's/.*PNG image data, \([0-9]\+\) x \([0-9]\+\).*/\1 \2/p')
  set -- $dims
  [ "$1" = "$2" ]
  [ "$1" -ge 64 ]
}
