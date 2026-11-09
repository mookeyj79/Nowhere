#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Cross-shell parity: consumes tests/parity.txt, the same list
# tests/powershell/Parity.Tests.ps1 consumes (format: the header of
# parity.txt). One zsh session per role+tools+local group.

scenario_parity() {
    local file=$REPO_ROOT/tests/parity.txt
    local rows groups bad=0 checked=0
    rows=$(tr -d '\r' < "$file" | grep -v -e '^#' -e '^$' | awk -F'|' '$2 == "both" || $2 == "zsh"')
    [ -n "$rows" ] || fail "no parity rows for zsh"
    groups=$(printf '%s\n' "$rows" | awk -F'|' '{print $3 "|" $4 "|" $5}' | sort -u)
    local role tools ovr id r t l check arg expect got pair probe
    while IFS='|' read -r role tools ovr; do
        probe=""
        while IFS='|' read -r id _ r t l check arg expect; do
            [ "$r|$t|$l" = "$role|$tools|$ovr" ] || continue
            case "$check" in
                cmd) probe+="whence -- '$arg' > /dev/null 2>&1 && echo 'P:$id=present' || echo 'P:$id=absent'; " ;;
                env) probe+="echo \"P:$id=\$$arg\"; " ;;
                hint) ;;
                *) fail "unknown check $check ($id)" ;;
            esac
        done <<< "$rows"
        reset_session
        case "$tools" in
            -) SESSION_TOOLS='' ;;
            core) SESSION_TOOLS=$CORE_TOOLS; SESSION_PLUGINS=$ALL_PLUGINS ;;
            *) SESSION_TOOLS=${tools//,/ } ;;
        esac
        case "$ovr" in
            -) ;;
            empty) SESSION_LOCAL='' ;;
            *)
                SESSION_LOCAL=''
                while IFS= read -r pair; do
                    SESSION_LOCAL+="${pair%%=*}='${pair#*=}'"$'\n'
                done <<< "${ovr//;/$'\n'}"
                ;;
        esac
        session "$([ "$role" = unset ] && echo '' || echo "$role")" "${probe}echo done"
        [ "$CODE" = 0 ] || { echo "    parity [$role|$tools|$ovr]: exit $CODE" >&2; bad=1; }
        [ -z "$ERR" ] || { echo "    parity [$role|$tools|$ovr]: stderr: $ERR" >&2; bad=1; }
        while IFS='|' read -r id _ r t l check arg expect; do
            [ "$r|$t|$l" = "$role|$tools|$ovr" ] || continue
            checked=$((checked + 1))
            if [ "$check" = hint ]; then
                got=$(count_matching "$OUT" 'run bootstrap')
            else
                got=$(printf '%s\n' "$OUT" | sed -n "s/^P:$id=//p")
            fi
            [ "$got" = "$expect" ] || { echo "    parity $id: expected [$expect], got [$got]" >&2; bad=1; }
        done <<< "$rows"
    done <<< "$groups"
    [ "$checked" -gt 0 ] || fail "nothing checked"
    [ "$bad" -eq 0 ]
}
