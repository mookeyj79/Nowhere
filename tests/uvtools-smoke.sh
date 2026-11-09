#!/bin/sh
# Smoke test for the uvTools pins in shared/tools.json: install each one with
# the real uv (network, no fakes) into a throwaway tool dir and run its --help.
# The sandbox suites fake uv, so this is what catches a pin that cannot resolve
# (not on PyPI, a missing commit) or a tool that cannot import on this OS,
# before a fresh server's bootstrap does. Specs come from the install plan
# (bootstrap/lib/plan.sh), every role. Needs uv, jq and bash.
# Usage: sh tests/uvtools-smoke.sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export UV_TOOL_DIR="$tmp/tools" UV_TOOL_BIN_DIR="$tmp/bin"

for role in devbox server; do
    bash "$root/bootstrap/lib/plan.sh" "$role" --arch -
done | awk -F'\t' '$1 == "uvtool" { print $2 "\t" $3 }' | sort -u > "$tmp/specs"
[ -s "$tmp/specs" ] || { echo "no uvTools in the install plan" >&2; exit 1; }

while IFS="$(printf '\t')" read -r name spec; do
    echo "==> uv tool install $spec"
    uv tool install "$spec"
    "$UV_TOOL_BIN_DIR/$name" --help > /dev/null
    echo "ok   $name"
done < "$tmp/specs"
