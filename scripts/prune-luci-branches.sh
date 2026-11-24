#!/bin/sh
# shellcheck disable=SC1007,SC2013,SC2015
# Delete superseded luci-update-* branches.
#
# luci-watch names its branch after the upstream commit, so every new upstream
# commit is a new branch name. A run that pushes its branch and then fails before
# opening the PR leaves one behind that no later run will ever look at. This
# removes those, and only those:
#
#   - never the branch passed with --keep (the one this run just pushed);
#   - never a branch that still has an open pull request (someone is reviewing);
#   - never anything outside the luci-update-* namespace.
set -eu

LC_ALL=C
TZ=UTC
export LC_ALL TZ

usage() {
	cat >&2 <<'EOF'
usage: prune-luci-branches.sh --keep <branch> [--dry-run]
EOF
	exit 2
}

keep= dry_run=0
while [ $# -gt 0 ]; do
	case "$1" in
		--keep)
			[ $# -ge 2 ] || usage
			keep=$2
			shift 2
			;;
		--dry-run) dry_run=1; shift ;;
		-h|--help) usage ;;
		*) usage ;;
	esac
done

[ -n "$keep" ] || usage
case "$keep" in
	luci-update-?*) ;;
	*) echo "--keep must be a luci-update-<sha> branch, got: $keep" >&2; exit 2 ;;
esac

deleted=0
kept=0

# A failure here must not look like "there was nothing to prune": that would let
# orphans accumulate while the job stays green.
if ! refs=$(git ls-remote --heads origin 'luci-update-*' 2>/dev/null); then
	echo "::warning::could not list luci-update-* branches; skipping cleanup"
	exit 0
fi

# Branch names cannot contain glob characters (git check-ref-format rejects
# them), but disable globbing anyway and re-check the namespace per item rather
# than trusting the remote listing.
set -f
for ref in $(printf '%s\n' "$refs" | awk '{print $2}'); do
	stale=${ref#refs/heads/}

	case "$stale" in
		luci-update-?*) ;;
		*) continue ;;
	esac

	# The branch this run pushed; its PR was just created or updated.
	if [ "$stale" = "$keep" ]; then
		kept=$((kept + 1))
		continue
	fi

	# A branch with an open PR is under review, not stale. A failed lookup is
	# not the same thing: keep the branch, but say so, or a broken token would
	# silently look like "everything is under review".
	if ! pr_count=$(gh pr list --head "$stale" --state open --json number --jq 'length' 2>/dev/null); then
		echo "::warning::could not read the PR state of $stale; keeping it"
		kept=$((kept + 1))
		continue
	fi
	if [ "$pr_count" != "0" ]; then
		echo "keeping $stale: it has an open pull request"
		kept=$((kept + 1))
		continue
	fi

	if [ "$dry_run" -eq 1 ]; then
		echo "would delete $stale"
		deleted=$((deleted + 1))
		continue
	fi

	if git push origin --delete "$stale" >/dev/null 2>&1; then
		echo "deleted superseded branch $stale"
		deleted=$((deleted + 1))
	else
		# Housekeeping must not fail a run whose PR was already created.
		echo "::warning::could not delete superseded branch $stale"
		kept=$((kept + 1))
	fi
done

echo "pruned: deleted=$deleted kept=$kept"
