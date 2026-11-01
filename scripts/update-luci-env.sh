#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Mirror the upstream luci-app-netbird Makefile version into versions/luci-app-netbird.env.
#
# The package version is whatever the upstream Makefile pins: bumping only our
# copy of the release number makes the env disagree with the ipk the SDK will
# actually build, which the release assertion then rejects.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: update-luci-env.sh --env-file <file> --commit <sha> --makefile <path>
EOF
	exit 2
}

env_file= commit= makefile=
while [ $# -gt 0 ]; do
	case "$1" in
		--env-file) env_file=$2; shift 2 ;;
		--commit) commit=$2; shift 2 ;;
		--makefile) makefile=$2; shift 2 ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$env_file" ] && [ -n "$commit" ] && [ -n "$makefile" ] || usage
[ -f "$makefile" ] || { echo "no such Makefile: $makefile" >&2; exit 1; }

pkg_version=$(sed -n 's/^PKG_VERSION:=//p' "$makefile" | head -n 1)
pkg_release=$(sed -n 's/^PKG_RELEASE:=//p' "$makefile" | head -n 1)
[ -n "$pkg_version" ] && [ -n "$pkg_release" ] \
	|| { echo "Makefile does not pin PKG_VERSION/PKG_RELEASE: $makefile" >&2; exit 1; }

before=$(cat "$env_file" 2>/dev/null || :)
printf 'LUCI_VERSION=%s\nLUCI_COMMIT=%s\nLUCI_PKG_RELEASE=%s\n' \
	"$pkg_version" "$commit" "$pkg_release" > "$env_file"
if [ "$before" = "$(cat "$env_file")" ]; then
	echo "CHANGED=0"
else
	echo "CHANGED=1"
fi
