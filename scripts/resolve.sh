#!/bin/sh
# Resolve a wayfinder ticket: comment, close, append to the map's Decisions so far, then show the fog to re-read.
# Usage: scripts/resolve.sh <ticket> <comment-file> <gist> [map-number]   (default map 1)
n="$1"; file="$2"; gist="$3"; map="${4:-1}"
if [ -z "$n" ] || [ ! -f "$file" ] || [ -z "$gist" ]; then echo "usage: $0 <ticket> <comment-file> <gist> [map]" >&2; exit 2; fi
title="$(gh issue view "$n" --json title --jq .title)" || exit 1
url="$(gh issue view "$n" --json url --jq .url)" || exit 1
gh issue comment "$n" --body-file "$file" >/dev/null || exit 1
gh issue close "$n" >/dev/null || exit 1
"$(dirname "$0")/map-append.sh" "Decisions so far" "- [$title]($url): $gist" "$map" || exit 1
echo "--- Not yet specified: clear or graduate every line this answer touches ---"
gh issue view "$map" --json body --jq .body | tr -d '\r' | awk '/^## /{p=($0=="## Not yet specified");next} p'
