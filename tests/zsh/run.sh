#!/usr/bin/env bash
# zsh sandbox harness. Checks the scenario index (tests/zsh/index.sh), then runs
# every scenario it lists for zsh.
# Usage: tests/zsh/run.sh [scenario-id ...]
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/zsh/lib.sh
. "$here/lib.sh"
# shellcheck source=tests/zsh/index.sh
. "$here/index.sh"
# shellcheck source=tests/zsh/scenarios.sh
. "$here/scenarios.sh"
for extra in "$here"/scenarios-*.sh; do
    [ -e "$extra" ] || continue
    # shellcheck source=/dev/null
    . "$extra"
done
# Sandboxes are made inside scenario subshells, so SANDBOXES cannot track them;
# a per-run TMPDIR holds them all and goes at exit.
TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/nowhere-run.XXXXXX")
export TMPDIR
trap 'cleanup_sandboxes; rm -rf "$TMPDIR"' EXIT

[ -n "$ZSH_BIN" ] || { echo "zsh not found on PATH" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq not found on PATH" >&2; exit 2; }

want=("$@")
pass=0; failed=0
# The index and the scenario_* functions must agree before anything runs.
if check_scenario_index; then echo "ok   scenario-index"; pass=$((pass + 1)); else echo "FAIL scenario-index"; failed=$((failed + 1)); fi
while IFS='|' read -r id shells _; do
    case "$shells" in zsh | both) ;; *) continue ;; esac
    if [ ${#want[@]} -gt 0 ] && [[ ! " ${want[*]} " == *" $id "* ]]; then continue; fi
    fn=scenario_${id//-/_}
    declare -F "$fn" > /dev/null || continue   # reported by check_scenario_index
    if ( set -u; "$fn" ); then echo "ok   $id"; pass=$((pass + 1)); else echo "FAIL $id"; failed=$((failed + 1)); fi
done < <(read_scenario_index 2> /dev/null)

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
