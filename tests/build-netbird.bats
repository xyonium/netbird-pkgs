#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/build-netbird.sh"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/src/client"
  printf 'package main\nfunc main(){}\n' > "$TMP/src/client/main.go"
  cat > "$TMP/fake-go" <<'GO'
#!/bin/sh
if [ "$1" = version ]; then echo "go version $FAKE_GO_VERSION linux/amd64"; exit 0; fi
if [ "$1" = build ]; then
  while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ]; then out=$2; fi
    shift
  done
  printf '#!/bin/sh\necho "0.82.0"\n' > "$out"
  chmod +x "$out"
  exit 0
fi
exit 1
GO
  chmod +x "$TMP/fake-go"
}

teardown() { rm -rf "$TMP"; }

@test "dry-run prints the pinned build command" {
  GO="$TMP/fake-go" FAKE_GO_VERSION=go1.26.2 SOURCE_DATE_EPOCH=1700000000 \
    run "$SCRIPT" --arch aarch64_generic --version 0.82.0 --commit deadbeef \
      --source "$TMP/src" --outdir "$TMP/out" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"CGO_ENABLED=0"* ]]
  [[ "$output" == *"GOOS=linux"* ]]
  [[ "$output" == *"GOARCH=arm64"* ]]
  [[ "$output" == *"GOTOOLCHAIN=local"* ]]
  [[ "$output" == *"GOFLAGS=-mod=readonly"* ]]
  [[ "$output" == *"-trimpath"* ]]
  [[ "$output" == *"-buildvcs=false"* ]]
  [[ "$output" == *"-buildmode=exe"* ]]
  [[ "$output" == *"-tags load_wgnt_from_rsrc"* ]]
  [[ "$output" == *"version.version=0.82.0"* ]]
  [[ "$output" == *"main.commit=deadbeef"* ]]
  [[ "$output" == *"main.date=1700000000"* ]]
  [[ "$output" == *"main.builtBy=netbird-pkgs"* ]]
  [[ "$output" == *"./client"* ]]
}

@test "rejects a mismatched Go toolchain" {
  GO="$TMP/fake-go" FAKE_GO_VERSION=go1.25.0 SOURCE_DATE_EPOCH=1700000000 \
    run "$SCRIPT" --arch x86_64 --version 0.82.0 --commit deadbeef \
      --source "$TMP/src" --outdir "$TMP/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"go1.26.2"* ]]
}

@test "requires SOURCE_DATE_EPOCH" {
  GO="$TMP/fake-go" FAKE_GO_VERSION=go1.26.2 \
    run "$SCRIPT" --arch x86_64 --version 0.82.0 --commit deadbeef \
      --source "$TMP/src" --outdir "$TMP/out"
  [ "$status" -eq 2 ]
}

@test "builds and verifies the binary version" {
  GO="$TMP/fake-go" FAKE_GO_VERSION=go1.26.2 SOURCE_DATE_EPOCH=1700000000 \
    run "$SCRIPT" --arch x86_64 --version 0.82.0 --commit deadbeef \
      --source "$TMP/src" --outdir "$TMP/out"
  [ "$status" -eq 0 ]
  [ -x "$TMP/out/netbird" ]
}
