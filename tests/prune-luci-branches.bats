#!/usr/bin/env bats

# Deleting remote branches is destructive, so the policy is tested against stub
# git/gh rather than by grepping the workflow.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/prune-luci-branches.sh"
  TMP="$(mktemp -d)"
  STUBS="$TMP/bin"
  mkdir -p "$STUBS"
  CALLS="$TMP/calls"

  cat > "$STUBS/git" <<'GIT'
#!/bin/sh
case "$1" in
  ls-remote)
    printf '%s\n' \
      "111 refs/heads/luci-update-AAAA" \
      "222 refs/heads/luci-update-BBBB" \
      "333 refs/heads/luci-update-CCCC"
    ;;
  push)
    echo "git $*" >> "$CALLS"
    # CCCC fails to delete, to exercise the warning path; others succeed.
    case "$*" in
      *--delete*CCCC*) exit 1 ;;
    esac
    ;;
esac
GIT

  cat > "$STUBS/gh" <<'GH'
#!/bin/sh
# Only BBBB has an open pull request.
case "$*" in
  *"head luci-update-BBBB"*) echo 1 ;;
  *) echo 0 ;;
esac
GH

  chmod +x "$STUBS/git" "$STUBS/gh"
  export CALLS
}

teardown() { rm -rf "$TMP"; }

@test "deletes only branches that are neither the kept one nor under review" {
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  # AAAA is the current branch, BBBB has a PR, CCCC is stale -> only CCCC.
  [ "$(grep -c 'push origin --delete' "$CALLS")" -eq 1 ]
  grep -q -- '--delete luci-update-CCCC' "$CALLS"
  ! grep -q -- '--delete luci-update-AAAA' "$CALLS"
  ! grep -q -- '--delete luci-update-BBBB' "$CALLS"
}

@test "reports the branches it kept" {
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [[ "$output" == *"keeping luci-update-BBBB: it has an open pull request"* ]]
  # CCCC's delete fails in this fixture, so exactly that one is counted as kept
  # alongside AAAA and BBBB.
  [[ "$output" == *"deleted=0 kept=3"* ]]
}

@test "counts a successful delete" {
  # No test previously covered the success path, so a bug that stopped counting
  # deletions would have gone unnoticed.
  cat > "$STUBS/git" <<'GIT'
#!/bin/sh
case "$1" in
  ls-remote) printf '%s\n' "111 refs/heads/luci-update-AAAA" "333 refs/heads/luci-update-CCCC" ;;
  push) echo "git $*" >> "$CALLS" ;;
esac
GIT
  chmod +x "$STUBS/git"
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted superseded branch luci-update-CCCC"* ]]
  [[ "$output" == *"deleted=1 kept=1"* ]]
}

@test "a failed delete warns instead of failing the run" {
  # CCCC's delete fails; the run must still exit 0, because the PR it just
  # created is the thing that matters.
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::could not delete superseded branch luci-update-CCCC"* ]]
}

@test "--dry-run changes nothing but reports what it would delete" {
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would delete luci-update-CCCC"* ]]
  [ ! -s "$CALLS" ]
}

@test "refuses to run without --keep" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "refuses a --keep outside the automation namespace" {
  # Guards against being pointed at a human branch, which would make the
  # deletion set depend on someone else's naming.
  run "$SCRIPT" --keep main
  [ "$status" -eq 2 ]
}

@test "keeps every branch when the only candidate is the kept one" {
  cat > "$STUBS/git" <<'GIT'
#!/bin/sh
case "$1" in
  ls-remote) echo "111 refs/heads/luci-update-AAAA" ;;
  push) echo "git $*" >> "$CALLS" ;;
esac
GIT
  chmod +x "$STUBS/git"
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [[ "$output" == *"deleted=0"* ]]
}

@test "a failed branch listing warns instead of pretending there was nothing" {
  # Silently reporting deleted=0 would let orphans pile up while the job is green.
  cat > "$STUBS/git" <<'GIT'
#!/bin/sh
case "$1" in
  ls-remote) echo "fatal: could not read from remote" >&2; exit 128 ;;
  push) echo "git $*" >> "$CALLS" ;;
esac
GIT
  chmod +x "$STUBS/git"
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning::could not list"* ]]
  [ ! -s "$CALLS" ]
}

@test "keeps a branch when the pull-request lookup fails" {
  # Fail-safe direction: an unreadable PR state must never be read as "no PR".
  cat > "$STUBS/gh" <<'GH'
#!/bin/sh
echo "boom: could not reach GitHub" >&2
exit 1
GH
  chmod +x "$STUBS/gh"
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  # It must say the lookup failed, not pretend the branch has an open PR.
  [[ "$output" == *"::warning::could not read the PR state"* ]]
  [[ "$output" != *"it has an open pull request"* ]]
}

@test "rejects --keep with no value instead of crashing" {
  run "$SCRIPT" --keep
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "rejects an empty --keep suffix" {
  run "$SCRIPT" --keep "luci-update-"
  [ "$status" -eq 2 ]
}

@test "ignores anything outside the namespace even if the listing returns it" {
  # git forbids glob characters in refnames and ls-remote is asked for
  # luci-update-*, so this should not happen; the per-item guard means a
  # surprising listing can never turn into a deletion of something else.
  cat > "$STUBS/git" <<'GIT'
#!/bin/sh
case "$1" in
  ls-remote) printf '%s\n' \
      "111 refs/heads/luci-update-AAAA" \
      "999 refs/heads/main" \
      "998 refs/heads/dependabot/github_actions/actions/checkout-7.0.1" ;;
  push) echo "git $*" >> "$CALLS" ;;
esac
GIT
  chmod +x "$STUBS/git"
  PATH="$STUBS:$PATH" run "$SCRIPT" --keep luci-update-AAAA
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
  [[ "$output" == *"deleted=0"* ]]
}
