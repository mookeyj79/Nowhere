#!/bin/sh
# Smoke test for the uvTools pins in shared/tools.json: install each one with
# the real uv (network, no fakes) into a throwaway tool dir and run its --help.
# The sandbox suites fake uv, so this is what catches a pin that cannot resolve
# (not on PyPI, a missing commit) or a tool that cannot import on this OS,
# before a fresh server's bootstrap does. Specs come from the install plan
# (bootstrap/lib/plan.sh), every role.
#
# It also asks pins whether each installed tool is at its pin, against the
# listing the real uv prints: the fakes print the format pins expects, so only
# this catches a uv whose listing pins would not recognise (every `update`
# would then reinstall the tool). The rule is uvtool-pin.sh on Linux and
# UvToolPin.ps1 (through pwsh) on Windows.
#
# Needs uv, jq and bash; pwsh on Windows.
# Usage: sh tests/uvtools-smoke.sh
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export UV_TOOL_DIR="$tmp/tools" UV_TOOL_BIN_DIR="$tmp/bin"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) windows=true ;;
    *) windows=false ;;
esac

# pinned <spec> <listing file>: pins' answer to "is <spec> installed at its pin?"
pinned() {
    if $windows; then
        pwsh -NoProfile -NonInteractive -Command "
            . '$(cygpath -w "$root/bootstrap/lib/UvToolPin.ps1")'
            if (Test-NowhereUvToolPinned -Spec '$1' -Listed @(Get-Content -LiteralPath '$(cygpath -w "$2")')) { exit 0 } else { exit 1 }"
    else
        bash -c '. "$1"; uv_pinned "$2" "$(cat "$3")"' _ "$root/bootstrap/lib/uvtool-pin.sh" "$1" "$2"
    fi
}

# a spec for the same tool at a pin nobody installed
other_pin() {
    case "$1" in
        *" @ "*) echo "${1%@*}@0000000000000000000000000000000000000000" ;;
        *) echo "${1%%==*}==0.0.0" ;;
    esac
}

for role in devbox server; do
    bash "$root/bootstrap/lib/plan.sh" "$role" --arch -
done | awk -F'\t' '$1 == "uvtool" { print $2 "\t" $3 }' | sort -u > "$tmp/specs"
[ -s "$tmp/specs" ] || { echo "no uvTools in the install plan" >&2; exit 1; }

while IFS="$(printf '\t')" read -r name spec; do
    echo "==> uv tool install $spec"
    uv tool install "$spec"
    "$UV_TOOL_BIN_DIR/$name" --help > /dev/null
    uv tool list --show-version-specifiers > "$tmp/listing"
    if ! pinned "$spec" "$tmp/listing"; then
        echo "pins does not recognise $spec as installed; uv tool list printed:" >&2
        cat "$tmp/listing" >&2
        exit 1
    fi
    other=$(other_pin "$spec")
    if pinned "$other" "$tmp/listing"; then
        echo "pins wrongly takes $other as installed; uv tool list printed:" >&2
        cat "$tmp/listing" >&2
        exit 1
    fi
    echo "ok   $name (installed, runs, recognised at its pin)"
done < "$tmp/specs"
