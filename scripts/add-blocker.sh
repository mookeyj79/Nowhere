#!/bin/sh
# Make <blocker> block <child> with GitHub's native issue dependency.
# Usage: scripts/add-blocker.sh <child> <blocker>
child="$1"; blocker="$2"
if [ -z "$child" ] || [ -z "$blocker" ]; then echo "usage: $0 <child> <blocker>" >&2; exit 2; fi
id="$(gh api "repos/{owner}/{repo}/issues/$blocker" --jq .id)" || exit 1
gh api --method POST "repos/{owner}/{repo}/issues/$child/dependencies/blocked_by" -F issue_id="$id" >/dev/null || exit 1
echo "#$blocker blocks #$child"
