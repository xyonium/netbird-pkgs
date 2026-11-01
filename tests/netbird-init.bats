#!/usr/bin/env bats

setup() {
  INIT="$BATS_TEST_DIRNAME/../packaging/netbird/netbird.init"
  TMP="$(mktemp -d)"
  PARAMS="$TMP/params"
}

teardown() {
  rm -rf "$TMP"
}

@test "whitelist only NB_LOG_FILE NB_LOG_LEVEL SSL_CERT_FILE" {
  source "$INIT"
  procd_append_param() { echo "$*" >> "$PARAMS"; }
  printf '%s\n' \
    'NB_LOG_FILE=syslog' \
    'NB_LOG_LEVEL="debug"' \
    'SSL_CERT_FILE=/etc/ssl/certs/ca.pem' \
    'NB_STATE_DIR=/evil' \
    'NOT_WHITELISTED=1' > "$TMP/env"
  append_env_from_file "$TMP/env"
  run cat "$PARAMS"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "env NB_LOG_FILE=syslog" ]
  [ "${lines[1]}" = "env NB_LOG_LEVEL=debug" ]
  [ "${lines[2]}" = "env SSL_CERT_FILE=/etc/ssl/certs/ca.pem" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "ignores comments, blank lines, garbage and a missing file" {
  source "$INIT"
  procd_append_param() { echo "$*" >> "$PARAMS"; }
  printf '%s\n' '# comment' '' 'garbage' 'NB_LOG_FILE=syslog' > "$TMP/env"
  append_env_from_file "$TMP/env"
  append_env_from_file "$TMP/missing"
  [ "$(wc -l < "$PARAMS")" -eq 1 ]
}

@test "parses a final line without a trailing newline" {
  source "$INIT"
  procd_append_param() { echo "$*" >> "$PARAMS"; }
  printf 'NB_LOG_FILE=syslog\nSSL_CERT_FILE=/etc/ssl/certs/ca.pem' > "$TMP/env"
  append_env_from_file "$TMP/env"
  run cat "$PARAMS"
  [[ "$output" == *"SSL_CERT_FILE=/etc/ssl/certs/ca.pem"* ]]
}

@test "never sources /etc/netbird.env" {
  run grep -E '(^|[[:space:]])(\.|source)[[:space:]]+/etc/netbird\.env' "$INIT"
  [ "$status" -eq 1 ]
}

@test "declares the pinned runtime paths and respawn" {
  run grep -E 'NB_CONFIG=/etc/netbird/config\.json' "$INIT"
  [ "$status" -eq 0 ]
  run grep -E 'NB_STATE_DIR=/etc/netbird' "$INIT"
  [ "$status" -eq 0 ]
  run grep -E 'NB_DNS_STATE_FILE=/var/lib/netbird/state\.json' "$INIT"
  [ "$status" -eq 0 ]
  run grep -E 'respawn 3600 5 5' "$INIT"
  [ "$status" -eq 0 ]
}
