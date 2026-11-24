#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Install the host packages an OpenWrt SDK build needs, then prove they work.
#
# Do not rely on the runner image for these. ubuntu-latest moved from 24.04 to
# 26.04 and stopped shipping libncurses-dev; the SDK's .prereq-build then failed
# with a message the CI log rendered as nothing at all, which cost a week of red
# builds before anyone could see why. The explicit checks below turn a missing
# package into a named failure.
set -eu

apt_opts="--no-install-recommends"
if [ "$(id -u)" -eq 0 ]; then
	apt-get update
	# shellcheck disable=SC2086
	apt-get install -y $apt_opts \
		build-essential libncurses-dev pkg-config gawk gettext \
		rsync unzip zlib1g-dev libssl-dev file wget
else
	sudo apt-get update
	# shellcheck disable=SC2086
	sudo apt-get install -y $apt_opts \
		build-essential libncurses-dev pkg-config gawk gettext \
		rsync unzip zlib1g-dev libssl-dev file wget
fi

# .prereq-build compiles against ncurses.h and links -lncurses.
echo 'int main(void){return 0;}' \
	| gcc -include ncurses.h -x c -o /dev/null - -lncurses \
	|| { echo "libncurses-dev is missing or unusable: the SDK cannot run its .prereq-build check" >&2; exit 1; }

# The SDK's conf tool (scripts/config/mconf-cfg.sh) looks for ncursesw first,
# then ncurses, through pkg-config.
if ! pkg-config --exists ncursesw && ! pkg-config --exists ncurses; then
	echo "pkg-config cannot find ncurses: the SDK cannot build its conf tool" >&2
	exit 1
fi

echo "SDK host dependencies present"
