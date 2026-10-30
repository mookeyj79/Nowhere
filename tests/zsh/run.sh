#!/usr/bin/env bash
# zsh sandbox harness. Runs every scenario in tests/scenarios.txt that lists zsh.
# Usage: tests/zsh/run.sh [scenario-id ...]
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/zsh/lib.sh
. "$here/lib.sh"
# shellcheck source=tests/zsh/scenarios.sh
. "$here/scenarios.sh"
for f in "$here"/scenarios-*.sh; do
    [ -e "$f" ] || continue
    # shellcheck source=/dev/null
    . "$f"
done
trap cleanup_sandboxes EXIT

[ -n "$ZSH_BIN" ] || { echo "zsh not found on PATH" >&2; exit 2; }
command -v jq > /dev/null || { echo "jq not found on PATH" >&2; exit 2; }

want=("$@")
pass=0; failed=0
while IFS='|' read -r id shells _; do
    case "$id" in '' | '#'*) continue ;; esac
    case "$shells" in *zsh* | both) ;; *) continue ;; esac
    if [ ${#want[@]} -gt 0 ] && [[ ! " ${want[*]} " == *" $id "* ]]; then continue; fi
    fn=scenario_${id//-/_}
    if ! declare -F "$fn" > /dev/null; then
        echo "FAIL $id (no implementation $fn)"; failed=$((failed + 1)); continue
    fi
    if ( set -u; "$fn" ); then echo "ok   $id"; pass=$((pass + 1)); else echo "FAIL $id"; failed=$((failed + 1)); fi
done < "$here/../scenarios.txt"

echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
