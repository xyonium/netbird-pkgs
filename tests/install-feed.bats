#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/install-feed.sh"
  TMP="$(mktemp -d)"
  ROOT="$TMP/root"
  mkdir -p "$ROOT/etc/opkg/keys" "$TMP/bin"
  cat > "$TMP/bin/opkg" <<'OPKG'
#!/bin/sh
if [ "$1" = print-architecture ]; then
  printf 'arch all 1\narch noarch 1\narch aarch64_generic 5\narch aarch64_cortex-a53 10\n'
  exit 0
fi
exit 1
OPKG
  chmod +x "$TMP/bin/opkg"
  if ! command -v usign >/dev/null 2>&1; then
    skip "usign not installed"
  fi
  usign -G -s "$TMP/key.sec" -p "$TMP/key.pub" -c test >/dev/null 2>&1
}

teardown() { rm -rf "$TMP"; }

@test "picks the native feed arch over the iStore priority alias" {
  run env PATH="$TMP/bin:$PATH" "$SCRIPT" --feed-url "file://$TMP/feed" \
    --key-file "$TMP/key.pub" --arch auto --root "$ROOT" --yes
  [ "$status" -eq 0 ]
  grep -q '^src/gz netbird-pkgs file://' "$ROOT/etc/opkg/customfeeds.conf"
  grep -q 'aarch64_generic' "$ROOT/etc/opkg/customfeeds.conf"
}

@test "is idempotent for the feed line and imports the key by fingerprint" {
  run env PATH="$TMP/bin:$PATH" "$SCRIPT" --feed-url "file://$TMP/feed" \
    --key-file "$TMP/key.pub" --arch aarch64_generic --root "$ROOT" --yes
  [ "$status" -eq 0 ]
  run env PATH="$TMP/bin:$PATH" "$SCRIPT" --feed-url "file://$TMP/feed" \
    --key-file "$TMP/key.pub" --arch aarch64_generic --root "$ROOT" --yes
  [ "$status" -eq 0 ]
  [ "$(grep -c '^src/gz netbird-pkgs ' "$ROOT/etc/opkg/customfeeds.conf")" -eq 1 ]
  local fp
  fp="$(usign -F -p "$TMP/key.pub")"
  [ -f "$ROOT/etc/opkg/keys/$fp" ]
  [ "$(stat -c %a "$ROOT/etc/opkg/keys/$fp")" = "644" ]
}

@test "refuses to write without --yes" {
  run env PATH="$TMP/bin:$PATH" "$SCRIPT" --feed-url "file://$TMP/feed" \
    --key-file "$TMP/key.pub" --arch aarch64_generic --root "$ROOT"
  [ "$status" -eq 1 ]
  [ ! -f "$ROOT/etc/opkg/customfeeds.conf" ]
}
