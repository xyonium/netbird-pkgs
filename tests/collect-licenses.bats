#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/collect-licenses.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/mod/github.com/foo@v1.0.0" "$TMP/mod/github.com/bar@v2.0.0" "$TMP/mod/github.com/baz@v3.0.0"
  printf 'FOO LICENSE\n' > "$TMP/mod/github.com/foo@v1.0.0/LICENSE"
  printf 'BAR MIT\n' > "$TMP/mod/github.com/bar@v2.0.0/LICENSE.md"
}

teardown() { rm -rf "$TMP"; }

@test "collects notices sorted by module and records missing ones" {
  run "$SCRIPT" --mod-cache "$TMP/mod" --out "$TMP/NOTICES"
  [ "$status" -eq 0 ]
  run cat "$TMP/NOTICES"
  [ "${lines[0]}" = "===== github.com/bar@v2.0.0 =====" ]
  [[ "${lines[1]}" == *"BAR MIT"* ]]
  [[ "$output" == *"===== github.com/foo@v1.0.0 ====="* ]]
  [[ "$output" == *"FOO LICENSE"* ]]
  [[ "$output" == *"MISSING LICENSE: github.com/baz@v3.0.0"* ]]
}

@test "fails when the module cache does not exist" {
  run "$SCRIPT" --mod-cache "$TMP/none" --out "$TMP/NOTICES"
  [ "$status" -eq 1 ]
}
