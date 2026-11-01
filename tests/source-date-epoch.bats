#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/source-date-epoch.sh"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "prints the commit time of the last commit touching the version env" {
  run bash -c "cd '$REPO' && '$SCRIPT' --env-file versions/netbird.env"
  [ "$status" -eq 0 ]
  want=$(git -C "$REPO" log -1 --format=%ct -- versions/netbird.env)
  [ "$output" = "$want" ]
}

@test "refuses to answer from a shallow clone instead of drifting to HEAD time" {
  git clone --depth 1 "file://$REPO" "$TMP/shallow" >/dev/null 2>&1
  [ "$(git -C "$TMP/shallow" rev-parse --is-shallow-repository)" = "true" ]
  run bash -c "cd '$TMP/shallow' && '$REPO/scripts/source-date-epoch.sh' --env-file versions/netbird.env"
  [ "$status" -eq 1 ]
  [[ "$output" == *"shallow"* ]]
}

@test "fails when the version env was never committed" {
  cp -a "$REPO/versions" "$TMP/versions"
  printf 'NETBIRD_VERSION=9.9.9\n' > "$TMP/versions/untracked.env"
  run bash -c "cd '$REPO' && '$SCRIPT' --env-file '$TMP/versions/untracked.env'"
  [ "$status" -eq 1 ]
}

@test "requires --env-file" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "fails when the version env does not exist" {
  run bash -c "cd '$REPO' && '$SCRIPT' --env-file versions/nope.env"
  [ "$status" -eq 1 ]
}
