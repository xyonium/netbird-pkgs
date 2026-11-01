#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/resolve-upstream.sh"
  TMP="$(mktemp -d)"
  cat > "$TMP/release.json" <<'JSON'
{ "tag_name": "v0.82.0", "target_commitish": "deadbeefcafe" }
JSON
  printf 'tarball-bytes' > "$TMP/src.tar.gz"
  printf 'NETBIRD_VERSION=0.82.0\nNETBIRD_COMMIT=x\nNETBIRD_SHA256=y\nNETBIRD_PKG_RELEASE=2\n' > "$TMP/same.env"
  printf 'NETBIRD_VERSION=0.81.4\nNETBIRD_COMMIT=x\nNETBIRD_SHA256=y\nNETBIRD_PKG_RELEASE=1\n' > "$TMP/old.env"
}

teardown() { rm -rf "$TMP"; }

@test "reports a new version with commit and checksum" {
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/release.json" \
    --tarball "$TMP/src.tar.gz" --env-file "$TMP/old.env"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERSION=0.82.0"* ]]
  [[ "$output" == *"COMMIT=deadbeefcafe"* ]]
  [[ "$output" == *"SHA256=$(sha256sum "$TMP/src.tar.gz" | awk '{print $1}')"* ]]
  [[ "$output" == *"CHANGED=1"* ]]
}

@test "reports no change when the env already tracks the release" {
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/release.json" \
    --tarball "$TMP/src.tar.gz" --env-file "$TMP/same.env"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHANGED=0"* ]]
}

@test "rejects a missing tarball or fixture" {
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/release.json" \
    --tarball "$TMP/nope.tar.gz" --env-file "$TMP/old.env"
  [ "$status" -eq 1 ]
}
