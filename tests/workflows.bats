#!/usr/bin/env bats

setup() {
  WF="$BATS_TEST_DIRNAME/../.github/workflows"
}

@test "upstream-watch runs weekly and on demand with write access" {
  run grep -q 'schedule:' "$WF/upstream-watch.yml"
  [ "$status" -eq 0 ]
  run grep -q 'workflow_dispatch:' "$WF/upstream-watch.yml"
  [ "$status" -eq 0 ]
  run grep -q 'contents: write' "$WF/upstream-watch.yml"
  [ "$status" -eq 0 ]
}

@test "build-release is chained from upstream-watch and manually dispatchable" {
  run grep -q 'workflow_run:' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  run grep -q 'upstream-watch' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  run grep -q 'workflow_dispatch:' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
}

@test "signing and deployment use separate environments" {
  run grep -q 'environment: release' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  run grep -q 'environment: github-pages' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  run grep -q 'pages: write' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
}

@test "declares the required jobs" {
  for job in build build-luci sign-publish deploy-pages; do
    run grep -q "^  $job:" "$WF/build-release.yml"
    [ "$status" -eq 0 ]
  done
}

@test "never uses pull_request_target and pins every action to a full SHA" {
  run grep -r 'pull_request_target' "$WF"
  [ "$status" -eq 1 ]
  run bash -c "grep -rh 'uses:' '$WF' | grep -vE '@[0-9a-f]{40}([[:space:]]|$)'"
  [ "$status" -eq 1 ]
}
