#!/usr/bin/env bash
# Shared bats helpers.

# make_fixture_binary <path>: executable stub standing in for the netbird binary.
make_fixture_binary() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/bin/sh
echo "0.82.0"
STUB
  chmod 0755 "$path"
}

# make_fixture_ipk <dir> <package> <version> <arch>: minimal valid ipk for feed tests.
make_fixture_ipk() {
  local dir="$1" pkg="$2" ver="$3" arch="$4" work
  work="$(mktemp -d)"
  mkdir -p "$work/control" "$work/data/usr/bin"
  cat > "$work/control/control" <<CTRL
Package: $pkg
Version: $ver
Depends: kmod-wireguard, ca-bundle
Section: net
Category: Network
Architecture: $arch
Installed-Size: 1
Maintainer: test
License: BSD-3-Clause
Description: fixture
CTRL
  printf 'x' > "$work/data/usr/bin/$pkg"
  chmod 0755 "$work/data/usr/bin/$pkg"
  ( cd "$work/control" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf ../control.tar.gz ./control )
  ( cd "$work/data" && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf ../data.tar.gz ./usr )
  mkdir -p "$dir"
  ( cd "$work" && printf '2.0\n' > debian-binary \
    && tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -czf "$dir/${pkg}_${ver}_${arch}.ipk" ./debian-binary ./data.tar.gz ./control.tar.gz )
  rm -rf "$work"
}
