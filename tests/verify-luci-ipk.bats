#!/usr/bin/env bats

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/verify-luci-ipk.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/build/control" "$TMP/build/data/etc/config" "$TMP/build/data/usr/share/doc/luci-app-netbird"
  cat > "$TMP/build/control/control" <<'CTRL'
Package: luci-app-netbird
Version: 0.1.0-r26
Architecture: all
Description: fixture
CTRL
  printf "config netbird_bin 'binary'\n\toption binary_source 'opkg'\n" > "$TMP/build/data/etc/config/netbird_bin"
  printf 'Apache-2.0\n' > "$TMP/build/data/usr/share/doc/luci-app-netbird/LICENSE"
  printf 'NOTICE\n' > "$TMP/build/data/usr/share/doc/luci-app-netbird/NOTICE"
  ( cd "$TMP/build/control" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf ../control.tar.gz ./control )
  ( cd "$TMP/build/data" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf ../data.tar.gz ./etc ./usr )
  ( cd "$TMP/build" && printf '2.0\n' > debian-binary \
    && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$TMP/good.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
  cat > "$TMP/luci.env" <<'ENV'
LUCI_VERSION=0.1.0
LUCI_COMMIT=cd812d93f8ca6c4563b716518c4308f9c448ac2f
LUCI_PKG_RELEASE=26
ENV
}

teardown() { rm -rf "$TMP"; }

@test "accepts a well formed LuCI ipk and checks the version env" {
  run "$SCRIPT" --ipk "$TMP/good.ipk" --version-env "$TMP/luci.env"
  [ "$status" -eq 0 ]
}

@test "does not depend on the caller exporting the version variables" {
  run env -u LUCI_VERSION -u LUCI_PKG_RELEASE "$SCRIPT" --ipk "$TMP/good.ipk" --version-env "$TMP/luci.env"
  [ "$status" -eq 0 ]
}

@test "rejects a payload that lost its files" {
  mkdir -p "$TMP/empty/data/usr/share/doc/luci-app-netbird"
  printf 'Apache-2.0\n' > "$TMP/empty/data/usr/share/doc/luci-app-netbird/LICENSE"
  printf 'NOTICE\n' > "$TMP/empty/data/usr/share/doc/luci-app-netbird/NOTICE"
  ( cd "$TMP/empty/data" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$TMP/empty/data.tar.gz" ./usr )
  cp "$TMP/build/control.tar.gz" "$TMP/empty/control.tar.gz"
  ( cd "$TMP/empty" && printf '2.0\n' > debian-binary \
    && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$TMP/empty.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
  run "$SCRIPT" --ipk "$TMP/empty.ipk" --version-env "$TMP/luci.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"netbird_bin"* ]]
}

@test "rejects a release build that drifted from the version env" {
  sed -i 's/^LUCI_PKG_RELEASE=26$/LUCI_PKG_RELEASE=27/' "$TMP/luci.env"
  run "$SCRIPT" --ipk "$TMP/good.ipk" --version-env "$TMP/luci.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"0.1.0-r26"* ]]
}

@test "rejects a package that is not luci-app-netbird" {
  sed -i 's/^Package: .*/Package: something-else/' "$TMP/build/control/control"
  ( cd "$TMP/build/control" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf ../control.tar.gz ./control )
  ( cd "$TMP/build" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$TMP/other.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
  run "$SCRIPT" --ipk "$TMP/other.ipk" --version-env "$TMP/luci.env"
  [ "$status" -eq 1 ]
}

@test "rejects a package whose binary_source default reverted to release" {
  sed -i "s/option binary_source 'opkg'/option binary_source 'release'/" "$TMP/build/data/etc/config/netbird_bin"
  ( cd "$TMP/build/data" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf ../data.tar.gz ./etc ./usr )
  ( cd "$TMP/build" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$TMP/reverted.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
  run "$SCRIPT" --ipk "$TMP/reverted.ipk" --version-env "$TMP/luci.env"
  [ "$status" -eq 1 ]
}

@test "requires an ipk" {
  run "$SCRIPT" --version-env "$TMP/luci.env"
  [ "$status" -eq 2 ]
}
