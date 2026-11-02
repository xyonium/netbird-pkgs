#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/resolve-upstream.sh"
  TMP="$(mktemp -d)"
  cat > "$TMP/release.json" <<'JSON'
{ "tag_name": "v0.82.0", "target_commitish": "deadbeefcafe",
  "html_url": "https://github.com/netbirdio/netbird/releases/tag/v0.82.0" }
JSON
  printf 'tarball-bytes' > "$TMP/src.tar.gz"
  printf 'NETBIRD_VERSION=0.82.0\nNETBIRD_COMMIT=x\nNETBIRD_SHA256=%s\nNETBIRD_PKG_RELEASE=2\n' \
    "$(sha256sum "$TMP/src.tar.gz" | awk '{print $1}')" > "$TMP/same.env"
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

@test "uses an explicit commit over target_commitish" {
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/release.json" \
    --tarball "$TMP/src.tar.gz" --env-file "$TMP/old.env" --commit 3c00a978
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMMIT=3c00a978"* ]]
}

@test "rejects a missing tarball or fixture" {
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/release.json" \
    --tarball "$TMP/nope.tar.gz" --env-file "$TMP/old.env"
  [ "$status" -eq 1 ]
}

@test "rejects a fixture that belongs to a different repository" {
  cat > "$TMP/other.json" <<'JSON'
{ "tag_name": "v0.82.0", "target_commitish": "deadbeefcafe",
  "html_url": "https://github.com/someone-else/netbird/releases/tag/v0.82.0" }
JSON
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/other.json" \
    --tarball "$TMP/src.tar.gz" --env-file "$TMP/old.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"netbirdio/netbird"* ]]
}

@test "ignores asset uploader profiles when checking the repository" {
  # Real release JSON carries one html_url per asset uploader after the
  # release's own html_url; a greedy match would pick the wrong one.
  # Single line on purpose: gh api --jq-free output is one long JSON line, and a
  # greedy match on that line used to pick the last uploader's profile URL.
  printf '%s\n' '{"tag_name":"v0.82.0","target_commitish":"deadbeefcafe","html_url":"https://github.com/netbirdio/netbird/releases/tag/v0.82.0","assets":[{"html_url":"https://github.com/mlsmaycon","name":"a.ipk"},{"html_url":"https://github.com/apps/github-actions","name":"b.ipk"}]}' > "$TMP/noisy.json"
  run "$SCRIPT" --repo netbirdio/netbird --fixture "$TMP/noisy.json" \
    --tarball "$TMP/src.tar.gz" --env-file "$TMP/old.env"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERSION=0.82.0"* ]]
}
