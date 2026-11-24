#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/bump-netbird-release.sh"
  TMP="$(mktemp -d)"
  ENV="$TMP/netbird.env"
  cat > "$ENV" <<'ENV'
NETBIRD_VERSION=0.83.2
NETBIRD_COMMIT=6d4814d22726c16961be79409dfbf6a2b2f7537b
NETBIRD_SHA256=e6d4d36da04017919f98b3724e51e1fe9982d803495ada1cdbc718eb0394cc48
NETBIRD_PKG_RELEASE=1
ENV
}

teardown() { rm -rf "$TMP"; }

@test "increments the package release and reports it" {
  run "$SCRIPT" --env-file "$ENV"
  [ "$status" -eq 0 ]
  [ "$output" = "NETBIRD_PKG_RELEASE=2" ]
  grep -qx 'NETBIRD_PKG_RELEASE=2' "$ENV"
}

@test "leaves the rest of the file untouched" {
  before=$(grep -v '^NETBIRD_PKG_RELEASE=' "$ENV")
  "$SCRIPT" --env-file "$ENV" >/dev/null
  after=$(grep -v '^NETBIRD_PKG_RELEASE=' "$ENV")
  [ "$before" = "$after" ]
}

@test "is not idempotent by accident: two runs make r3" {
  "$SCRIPT" --env-file "$ENV" >/dev/null
  run "$SCRIPT" --env-file "$ENV"
  [ "$status" -eq 0 ]
  grep -qx 'NETBIRD_PKG_RELEASE=3' "$ENV"
}

@test "fails when the key is missing" {
  printf 'NETBIRD_VERSION=1.0.0\n' > "$ENV"
  run "$SCRIPT" --env-file "$ENV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not set"* ]]
}

@test "fails when the value is not a number" {
  sed -i 's/^NETBIRD_PKG_RELEASE=.*/NETBIRD_PKG_RELEASE=abc/' "$ENV"
  run "$SCRIPT" --env-file "$ENV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a number"* ]]
}

@test "fails on a missing file" {
  run "$SCRIPT" --env-file "$TMP/nope"
  [ "$status" -eq 1 ]
}

@test "requires --env-file" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
