#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/fetch-previous-ipks.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/bin" "$TMP/prev" "$TMP/releases"
  # Stub gh. RELEASES lists tags; <tag>.assets lists asset names and
  # <tag>.ipk.<name> holds an asset payload; FAIL_TAG makes the download fail.
  cat > "$TMP/bin/gh" <<'GH'
#!/bin/sh
set -eu
case "$1 $2" in
  "release list")
    printf '%s\n' ${RELEASES:-} ;;
  "release view")
    tag=$3
    [ -f "$STUB/releases/$tag.assets" ] || { echo "no such release: $tag" >&2; exit 1; }
    cat "$STUB/releases/$tag.assets" ;;
  "release download")
    tag=$3
    [ -f "$STUB/releases/$tag.assets" ] || { echo "no such release: $tag" >&2; exit 1; }
    if [ -n "${FAIL_TAG:-}" ] && [ "$FAIL_TAG" = "$tag" ]; then
      echo "stub gh: network error" >&2
      exit 1
    fi
    dir=
    prev=
    for a in "$@"; do
      [ "$prev" = "--dir" ] && dir=$a
      prev=$a
    done
    [ -n "$dir" ] || { echo "stub gh: no --dir" >&2; exit 1; }
    for f in "$STUB/releases/$tag".ipk.*; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      name=${name#"$tag.ipk."}
      cp "$f" "$dir/$name"
    done
    ;;
  *) echo "stub gh: unsupported $*" >&2; exit 1 ;;
esac
GH
  chmod +x "$TMP/bin/gh"
  export STUB="$TMP"
  PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

# release_ipk <tag> <filename>: mark a release as carrying one ipk asset.
release_ipk() {
  printf '%s\n' "$2" >> "$TMP/releases/$1.assets"
  printf 'payload-%s\n' "$2" > "$TMP/releases/$1.ipk.$2"
}

@test "downloads the ipks carried by previous releases" {
  release_ipk v0.81.4-r1 netbird_0.81.4-r1_aarch64_generic.ipk
  RELEASES="v0.81.4-r1"
  export RELEASES
  run "$SCRIPT" --dir "$TMP/prev" --limit 3
  [ "$status" -eq 0 ]
  [ -f "$TMP/prev/netbird_0.81.4-r1_aarch64_generic.ipk" ]
}

@test "skips a release that carries no ipk assets instead of failing" {
  release_ipk v0.81.4-r1 netbird_0.81.4-r1_aarch64_generic.ipk
  printf 'notes.tar.gz\n' > "$TMP/releases/v0.80.0-r1.assets"
  RELEASES="v0.81.4-r1 v0.80.0-r1"
  export RELEASES
  run "$SCRIPT" --dir "$TMP/prev" --limit 3
  [ "$status" -eq 0 ]
  [ -f "$TMP/prev/netbird_0.81.4-r1_aarch64_generic.ipk" ]
}

@test "fails loudly when a download fails" {
  release_ipk v0.81.4-r1 netbird_0.81.4-r1_x86_64.ipk
  RELEASES="v0.81.4-r1"
  FAIL_TAG="v0.81.4-r1"
  export RELEASES FAIL_TAG
  run "$SCRIPT" --dir "$TMP/prev" --limit 3
  [ "$status" -eq 1 ]
}

@test "never re-downloads the release being published" {
  release_ipk v0.82.0-r1 netbird_0.82.0-r1_x86_64.ipk
  RELEASES="v0.82.0-r1"
  export RELEASES
  run "$SCRIPT" --dir "$TMP/prev" --limit 3 --exclude v0.82.0-r1
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/prev/netbird_0.82.0-r1_x86_64.ipk" ]
}

@test "requires --dir" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
