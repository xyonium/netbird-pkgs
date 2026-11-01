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

@test "has push/PR CI and a LuCI watch workflow" {
  run grep -q 'pull_request:' "$WF/ci.yml"
  [ "$status" -eq 0 ]
  run grep -q 'schedule:' "$WF/luci-watch.yml"
  [ "$status" -eq 0 ]
  run grep -q 'gh pr create' "$WF/luci-watch.yml"
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

@test "upstream-watch checksums the codeload archive, not the API tarball_url" {
  run grep -q 'tarball_url' "$WF/upstream-watch.yml"
  [ "$status" -eq 1 ]
  run grep -q 'codeload.github.com/netbirdio/netbird/tar.gz/' "$WF/upstream-watch.yml"
  [ "$status" -eq 0 ]
}

@test "upstream-watch and build-release download from the same tarball base URL" {
  base='https://codeload.github.com/netbirdio/netbird/tar.gz/'
  run grep -Fq "$base" "$WF/upstream-watch.yml"
  [ "$status" -eq 0 ]
  run grep -Fq "$base" "$WF/build-release.yml"
  [ "$status" -eq 0 ]
}

@test "derives SOURCE_DATE_EPOCH through the shared script, never inline git log" {
  run grep -q 'git log -1 --format=%ct' "$WF/build-release.yml"
  [ "$status" -eq 1 ]
  run grep -q 'scripts/source-date-epoch.sh' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
}

@test "every release checkout fetches full history so the epoch is stable" {
  checkouts=$(grep -c 'actions/checkout' "$WF/build-release.yml")
  depths=$(grep -c 'fetch-depth: 0' "$WF/build-release.yml")
  [ "$checkouts" -eq "$depths" ]
}

@test "every workflow that runs the test suite installs the test dependencies" {
  for wf in "$WF"/*.yml; do
    grep -qE 'make (lint )?test' "$wf" || continue
    run grep -q 'scripts/install-test-deps.sh' "$wf"
    [ "$status" -eq 0 ]
    echo "checked $wf"
  done
}

@test "the test dependency installer provides usign, which the e2e flow signs with" {
  run grep -q 'usign' "$BATS_TEST_DIRNAME/../scripts/install-test-deps.sh"
  [ "$status" -eq 0 ]
}

@test "the reproducibility job packages the same inputs as the release build" {  run awk '
    { line = $0
      while (line ~ /\\$/) {
        sub(/\\$/, "", line)
        if ((getline nxt) > 0) { line = line " " nxt } else { break }
      }
      if (line ~ /build-netbird-ipk\.sh/) print line
    }' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  total=$(printf '%s\n' "$output" | grep -c 'build-netbird-ipk\.sh')
  noticed=$(printf '%s\n' "$output" | grep -c -- '--notices')
  [ "$total" -ge 2 ]
  [ "$total" -eq "$noticed" ]
}

@test "luci-watch mirrors the upstream Makefile instead of blind-bumping the release" {
  run grep -q 'scripts/update-luci-env.sh' "$WF/luci-watch.yml"
  [ "$status" -eq 0 ]
  run grep -q 'release + 1' "$WF/luci-watch.yml"
  [ "$status" -eq 1 ]
}

@test "the rollback fetch fails the release instead of silently dropping versions" {
  run grep -q 'scripts/fetch-previous-ipks.sh' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  run bash -c "grep 'gh release download' '$WF/build-release.yml' | grep -c '|| true'"
  [ "$status" -eq 1 ]
}

@test "every workflow that runs the test suite checks out full history" {
  for wf in "$WF"/*.yml; do
    grep -qE 'make (lint )?test' "$wf" || continue
    run grep -q 'fetch-depth: 0' "$wf"
    [ "$status" -eq 0 ]
    echo "checked $wf"
  done
}

@test "never passes gh api an output flag it does not have" {
  # gh api writes the body to stdout; it has no -o/--output flag.
  run bash -c "grep -rn 'gh api .* -o ' '$WF'"
  [ "$status" -eq 1 ]
}

@test "the LuCI build uses a pinned SDK release, not a floating container image" {
  run grep -q 'openwrt/gh-action-sdk' "$WF/build-release.yml"
  [ "$status" -eq 1 ]
  run grep -q 'scripts/build-luci-ipk.sh' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
  run grep -q 'LUCI_SDK_SHA256' "$WF/build-release.yml"
  [ "$status" -eq 0 ]
}

@test "the pinned LuCI SDK is recorded with a verifiable checksum" {
  env_file="$BATS_TEST_DIRNAME/../versions/luci-app-netbird.env"
  run grep -qE '^LUCI_SDK_VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$env_file"
  [ "$status" -eq 0 ]
  run grep -qE '^LUCI_SDK_SHA256=[0-9a-f]{64}$' "$env_file"
  [ "$status" -eq 0 ]
}
