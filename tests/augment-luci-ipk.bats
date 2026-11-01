#!/usr/bin/env bats
load helper
setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/augment-luci-ipk.sh"
  TMP="$(mktemp -d)"
  make_fixture_ipk "$TMP" luci-app-netbird 0.1.0-r26 all
  printf 'Apache-2.0\n' > "$TMP/LICENSE"
  printf 'NOTICE\n' > "$TMP/NOTICE"
  printf 'extra\n' > "$TMP/EXTRA"
}
teardown() { rm -rf "$TMP"; }
@test "adds license and notice documents to the ipk" {
  run "$SCRIPT" --ipk "$TMP/luci-app-netbird_0.1.0-r26_all.ipk" --license "$TMP/LICENSE" --notice "$TMP/NOTICE" --extra-notice "$TMP/EXTRA"
  [ "$status" -eq 0 ]
  run bash -c "tar -xOf '$TMP/luci-app-netbird_0.1.0-r26_all.ipk' ./data.tar.gz | tar -tzf -"
  [[ "$output" == *"doc/luci-app-netbird/LICENSE"* ]]
  [[ "$output" == *"doc/luci-app-netbird/NOTICE"* ]]
}
