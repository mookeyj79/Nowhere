#!/bin/sh
# Smoke test for the uvTools pins in shared/tools.json: install each one with
# the real uv (network, no fakes) into a throwaway tool dir and run its --help.
# The sandbox suites fake uv, so this is what catches a pin that cannot resolve
# (not on PyPI, a missing commit) or a tool that cannot import on this OS,
# before a fresh server's bootstrap does. Needs uv and jq.
# Usage: sh tests/uvtools-smoke.sh
set -eu
manifest="$(cd "$(dirname "$0")/.." && pwd)/shared/tools.json"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export UV_TOOL_DIR="$tmp/tools" UV_TOOL_BIN_DIR="$tmp/bin"

# Same spec rule as both bootstraps: 'source' gives name @ source, else name==version.
jq -r '.uvTools[] | [.name, (if .source then "\(.name) @ \(.source)" else "\(.name)==\(.version)" end)] | @tsv' "$manifest" > "$tmp/specs"
[ -s "$tmp/specs" ] || { echo "no uvTools in $manifest" >&2; exit 1; }

while IFS="$(printf '\t')" read -r name spec; do
    echo "==> uv tool install $spec"
    uv tool install "$spec"
    "$UV_TOOL_BIN_DIR/$name" --help > /dev/null
    echo "ok   $name"
done < "$tmp/specs"
