#!/usr/bin/env bats

load helper

setup() {
  BUILD="$BATS_TEST_DIRNAME/../scripts/build-netbird-ipk.sh"
  VERIFY="$BATS_TEST_DIRNAME/../scripts/verify-ipk.sh"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/static.go"
  TMP="$(mktemp -d)"
  export GOCACHE="${GOCACHE:-/tmp/gocache}"
  ( cd "$TMP" && CGO_ENABLED=0 go build -trimpath -o netbird "$FIXTURE" )
  printf 'BSD-3-Clause fixture\n' > "$TMP/LICENSE"
  run "$BUILD" --arch x86_64 --version 0.82.0 --pkg-release 1 \
    --binary "$TMP/netbird" --license "$TMP/LICENSE" --source-date-epoch 1700000000 \
    --outdir "$TMP/out"
  IPK="$TMP/out/netbird_0.82.0-r1_x86_64.ipk"
}

teardown() { rm -rf "$TMP"; }

# make_ipk <dir> <control-extra...>: build an ipk from given pieces.
make_raw_ipk() {
  local dir="$1" control="$2" binary="$3" init="$4" work
  work="$(mktemp -d)"
  mkdir -p "$work/data/usr/bin" "$work/data/etc/init.d" "$work/control"
  printf '%s\n' "$control" > "$work/control/control"
  cp "$binary" "$work/data/usr/bin/netbird"
  chmod 0755 "$work/data/usr/bin/netbird"
  printf '%s\n' "$init" > "$work/data/etc/init.d/netbird"
  chmod 0755 "$work/data/etc/init.d/netbird"
  tar -C "$work/control" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$work/control.tar.gz" ./control
  tar -C "$work/data" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$work/data.tar.gz" ./usr ./etc
  printf '2.0\n' > "$work/debian-binary"
  mkdir -p "$dir"
  tar -C "$work" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$dir/test.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz
  rm -rf "$work"
}

@test "accepts a valid ipk and checks the binary version" {
  run "$VERIFY" --ipk "$IPK" --arch x86_64 --version 0.82.0
  [ "$status" -eq 0 ]
}

@test "rejects a wrong architecture" {
  run "$VERIFY" --ipk "$IPK" --arch aarch64_generic
  [ "$status" -eq 1 ]
}

@test "rejects missing dependencies" {
  make_raw_ipk "$TMP/bad" "Package: netbird
Version: 0.82.0-r1
Depends: kmod-wireguard
Architecture: x86_64
Description: bad" "$TMP/netbird" "#!/bin/sh"
  run "$VERIFY" --ipk "$TMP/bad/test.ipk" --arch x86_64 --skip-binary-check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ca-bundle"* ]]
}

@test "rejects an init script with a syntax error" {
  make_raw_ipk "$TMP/bad" "Package: netbird
Version: 0.82.0-r1
Depends: kmod-wireguard, ca-bundle
Architecture: x86_64
Description: bad" "$TMP/netbird" "if then fi ("
  run "$VERIFY" --ipk "$TMP/bad/test.ipk" --arch x86_64 --skip-binary-check
  [ "$status" -eq 1 ]
}

@test "rejects a dynamically linked binary" {
  make_raw_ipk "$TMP/bad" "Package: netbird
Version: 0.82.0-r1
Depends: kmod-wireguard, ca-bundle
Architecture: x86_64
Description: bad" /bin/true "#!/bin/sh"
  run "$VERIFY" --ipk "$TMP/bad/test.ipk" --arch x86_64 --version 0.82.0
  [ "$status" -eq 1 ]
}

@test "rejects a version mismatch" {
  run "$VERIFY" --ipk "$IPK" --arch x86_64 --version 9.9.9
  [ "$status" -eq 1 ]
}

@test "skip-binary-check allows a dynamic fixture" {
  make_raw_ipk "$TMP/ok" "Package: netbird
Version: 0.82.0-r1
Depends: kmod-wireguard, ca-bundle
Architecture: x86_64
Description: ok" /bin/true "#!/bin/sh"
  run "$VERIFY" --ipk "$TMP/ok/test.ipk" --arch x86_64 --skip-binary-check
  [ "$status" -eq 0 ]
}
