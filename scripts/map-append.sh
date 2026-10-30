#!/bin/sh
# Append one line under a section of a wayfinder map body.
# Usage: scripts/map-append.sh <section> <line> [map-number]   (default map 1)
#   section: heading text without "## ", e.g. "Decisions so far"
map="${3:-1}"
section="$1"; line="$2"
if [ -z "$section" ] || [ -z "$line" ]; then echo "usage: $0 <section> <line> [map]" >&2; exit 2; fi
tmp="$(mktemp)"
gh issue view "$map" --json body --jq .body | tr -d '\r' | LINE="$line" awk -v sec="## $section" '
  { l[NR] = $0 }
  $0 == sec { s = NR; at = NR }
  s && NR > s && /^## / { s = 0 }
  s && NR > s && $0 !~ /^[[:space:]]*$/ && $0 !~ /^<!--/ { at = NR }
  END {
    if (!at) exit 1
    for (i = 1; i <= NR; i++) { print l[i]; if (i == at) print ENVIRON["LINE"] }
  }' > "$tmp" || { echo "section '$section' not found" >&2; rm -f "$tmp"; exit 1; }
gh issue edit "$map" --body-file "$tmp" >/dev/null && rm -f "$tmp" && echo "appended to '$section'"
