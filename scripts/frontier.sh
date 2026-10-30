#!/bin/sh
# Print a wayfinder map's frontier: open, unblocked, unassigned child tickets, in map order.
# Usage: scripts/frontier.sh [map-number]          (default 1)
#        scripts/frontier.sh --lint [map-number]   list open children that already carry a resolution comment
lint=0
[ "$1" = "--lint" ] && { lint=1; shift; }
map="${1:-1}"
if [ "$lint" = 1 ]; then
  for n in $(gh api "repos/{owner}/{repo}/issues/$map/sub_issues?per_page=100" --jq '.[] | select(.state == "open") | .number'); do
    gh issue view "$n" --json number,title,comments --jq '
      select(any(.comments[]; .body | test("^(Research )?[Rr]esolved")))
      | "#\(.number)\tresolved but open: close it and record it on the map\t\(.title)"'
  done
  exit 0
fi
gh api "repos/{owner}/{repo}/issues/$map/sub_issues?per_page=100" --jq '
  .[] | select(.state == "open"
               and .issue_dependencies_summary.blocked_by == 0
               and (.assignees | length) == 0)
      | "#\(.number)\t\(.labels | map(.name) | join(","))\t\(.title)"'
