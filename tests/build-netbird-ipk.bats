#!/usr/bin/env bats

load helper

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/build-netbird-ipk.sh"
  INIT="$BATS_TEST_DIRNAME/../packaging/netbird/netbird.init"
  TMP="$(mktemp -d)"
  make_fixture_binary "$TMP/netbird"
  printf 'BSD-3-Clause fixture\n' > "$TMP/LICENSE"
  printf 'third party fixture\n' > "$TMP/NOTICES"
}

teardown() {
  rm -rf "$TMP"
}

build() {
  "$SCRIPT" --arch "$1" --version 0.82.0 --pkg-release 1 \
    --binary "$TMP/netbird" --license "$TMP/LICENSE" --notices "$TMP/NOTICES" \
    --source-date-epoch 1700000000 --outdir "$TMP/out"
}

@test "rejects a missing or non-executable binary" {
  run "$SCRIPT" --arch aarch64_generic --version 0.82.0 \
    --binary "$TMP/nope" --license "$TMP/LICENSE" --source-date-epoch 1700000000 --outdir "$TMP/out"
  [ "$status" -eq 1 ]

  chmod 0644 "$TMP/netbird"
  run "$SCRIPT" --arch aarch64_generic --version 0.82.0 \
    --binary "$TMP/netbird" --license "$TMP/LICENSE" --source-date-epoch 1700000000 --outdir "$TMP/out"
  [ "$status" -eq 1 ]
}

@test "rejects an unsupported architecture with usage error" {
  run "$SCRIPT" --arch mips --version 0.82.0 --binary "$TMP/netbird" \
    --license "$TMP/LICENSE" --outdir "$TMP/out"
  [ "$status" -eq 2 ]
}

@test "assembles the OpenWrt ipk layout in order" {
  run build aarch64_generic
  [ "$status" -eq 0 ]
  local ipk="$TMP/out/netbird_0.82.0-r1_aarch64_generic.ipk"
  [ -f "$ipk" ]
  run tar tzf "$ipk"
  [ "${lines[0]}" = "./debian-binary" ]
  [ "${lines[1]}" = "./data.tar.gz" ]
  [ "${lines[2]}" = "./control.tar.gz" ]
}

@test "control has pinned fields and no conffiles" {
  run build x86_64
  [ "$status" -eq 0 ]
  local ipk="$TMP/out/netbird_0.82.0-r1_x86_64.ipk"
  local control
  control="$(tar -xOf "$ipk" ./control.tar.gz | tar -xzOf - ./control)"
  [[ "$control" == *"Package: netbird"* ]]
  [[ "$control" == *"Version: 0.82.0-r1"* ]]
  [[ "$control" == *"Architecture: x86_64"* ]]
  [[ "$control" == *"Depends: kmod-wireguard, ca-bundle"* ]]
  [[ "$control" == *"License: BSD-3-Clause"* ]]
  [[ "$control" == *"SourceDateEpoch: 1700000000"* ]]
  run tar tzf <(tar -xOf "$ipk" ./control.tar.gz)
  [[ "$output" != *"conffiles"* ]]
}

@test "data files carry the expected modes and paths" {
  run build aarch64_generic
  [ "$status" -eq 0 ]
  local ipk="$TMP/out/netbird_0.82.0-r1_aarch64_generic.ipk"
  local listing
  listing="$(tar -xOf "$ipk" ./data.tar.gz | tar -tvzf -)"
  [[ "$listing" == *"-rwxr-xr-x"*"./usr/bin/netbird"* ]]
  [[ "$listing" == *"-rwxr-xr-x"*"./etc/init.d/netbird"* ]]
  [[ "$listing" == *"./usr/share/licenses/netbird/LICENSE"* ]]
  [[ "$listing" == *"./usr/share/licenses/netbird/THIRD-PARTY-NOTICES.txt"* ]]
}

@test "same source date epoch yields an identical ipk" {
  run build aarch64_generic
  [ "$status" -eq 0 ]
  cp "$TMP/out/netbird_0.82.0-r1_aarch64_generic.ipk" "$TMP/first.ipk"
  run build aarch64_generic
  [ "$status" -eq 0 ]
  cmp "$TMP/first.ipk" "$TMP/out/netbird_0.82.0-r1_aarch64_generic.ipk"
  run cat "$TMP/out/netbird_0.82.0-r1_aarch64_generic.ipk.sha256"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TMP/out/netbird_0.82.0-r1_aarch64_generic.ipk.sha256")" -eq 1 ]
}
