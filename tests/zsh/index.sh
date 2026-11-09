#!/usr/bin/env bash
# The scenario index for the zsh harness (sourced by run.sh, never run directly).
#
# The index is tests/scenarios.txt plus tests/zsh/scenarios-*.txt, one record
# per line in the format the header of tests/scenarios.txt gives:
#   id|shells|pwsh counterpart|what it asserts
# tests/powershell/Parity.Tests.ps1 reads the same files for the pwsh column.

# read_scenario_index: every record, one per line. Each file is read on its
# own, line by line, so a file without a final newline cannot glue its last
# record onto the next file's first. A line that is not a record is named
# (file:line) on stderr and makes the status non-zero; the good records are
# still printed.
read_scenario_index() {
    local f n line bad=0
    local record='^[a-z0-9]+(-[a-z0-9]+)*\|(both|zsh)\|[^|]+\|[^|]+$'
    for f in "$REPO_ROOT/tests/scenarios.txt" "$REPO_ROOT"/tests/zsh/scenarios-*.txt; do
        n=0
        while IFS= read -r line || [ -n "$line" ]; do
            n=$((n + 1)); line=${line%$'\r'}
            case "$line" in '' | '#'*) continue ;; esac
            if [[ $line =~ $record ]]; then
                printf '%s\n' "$line"
            else
                echo "index: ${f#"$REPO_ROOT"/}:$n is not id|shells|pwsh|asserts: $line" >&2
                bad=1
            fi
        done < "$f"
    done
    return $bad
}

# check_scenario_index: the index and the scenario_* functions agree, both
# ways. Every id appears once, every zsh id has its scenario_<id> (dashes
# become underscores), and every scenario_* function is listed. Problems go
# to stderr; the status is non-zero if there were any.
check_scenario_index() {
    local records ids id fn dup bad=0
    records=$(read_scenario_index) || bad=1
    dup=$(cut -d'|' -f1 <<< "$records" | sort | uniq -d)
    if [ -n "$dup" ]; then echo "index: listed more than once: ${dup//$'\n'/ }" >&2; bad=1; fi
    ids=$(awk -F'|' '$2 == "both" || $2 == "zsh" { print $1 }' <<< "$records")
    for id in $ids; do
        fn=scenario_${id//-/_}
        declare -F "$fn" > /dev/null || { echo "index: $id has no $fn" >&2; bad=1; }
    done
    for fn in $(declare -F | awk '$3 ~ /^scenario_/ { print $3 }'); do
        id=${fn#scenario_}; id=${id//_/-}
        grep -qxF -- "$id" <<< "$ids" || { echo "index: $fn is not listed as a zsh scenario" >&2; bad=1; }
    done
    return $bad
}
