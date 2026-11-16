#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for zsh/core/conf.d/10-line-editor.zsh and 90-syntax-highlighting.zsh
# (ticket #15). Sourced by run.sh; ids and pwsh counterparts live in tests/scenarios.txt.

LE_ALL_PLUGINS="zsh-autosuggestions:zsh-autosuggestions.zsh:AS_LOADED zsh-history-substring-search:zsh-history-substring-search.zsh:HS_LOADED zsh-syntax-highlighting:zsh-syntax-highlighting.zsh:SYNTAX_LOADED"
LE_ALL_TOOLS=$CORE_TOOLS
LE_FZF_INIT='bindkey "^R" fzf-history-widget; bindkey "^T" fzf-file-widget; bindkey "^[c" fzf-cd-widget'
LE_KEYS='for k in "^I" "^[[Z" "^[[A" "^[OA" "^[[B" "^[OB" "^F" "^[f" "^R" "^T" "^[c"; do bindkey "$k"; done'

scenario_le_bindings() {
    reset_session; SESSION_TOOLS=$LE_ALL_TOOLS; SESSION_PLUGINS=$LE_ALL_PLUGINS; SESSION_FZF_ZSH=$LE_FZF_INIT
    session server "bindkey -lL main; $LE_KEYS"
    assert_empty "$ERR"
    assert_line "$OUT" 'bindkey -A emacs main'
    assert_line "$OUT" '"^I" menu-complete'
    assert_line "$OUT" '"^[[Z" reverse-menu-complete'
    assert_line "$OUT" '"^[[A" history-substring-search-up'
    assert_line "$OUT" '"^[OA" history-substring-search-up'
    assert_line "$OUT" '"^[[B" history-substring-search-down'
    assert_line "$OUT" '"^[OB" history-substring-search-down'
    assert_line "$OUT" '"^F" autosuggest-accept'
    assert_line "$OUT" '"^[f" forward-word'
    assert_line "$OUT" '"^R" fzf-history-widget'
    assert_line "$OUT" '"^T" fzf-file-widget'
    assert_line "$OUT" '"^[c" fzf-cd-widget'
}

scenario_le_ghost_style() {
    reset_session; SESSION_TOOLS=$LE_ALL_TOOLS; SESSION_PLUGINS=$LE_ALL_PLUGINS
    session server 'echo "style=$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"; echo "strategy=$ZSH_AUTOSUGGEST_STRATEGY"'
    assert_empty "$ERR"
    assert_line "$OUT" 'style=fg=8'
    assert_line "$OUT" 'strategy=history'
}

scenario_le_history() {
    reset_session; SESSION_TOOLS=$LE_ALL_TOOLS; SESSION_PLUGINS=$LE_ALL_PLUGINS
    # `[[ -o name ]]` fails for a name zsh does not know, so this also verifies
    # the option names. (Dedup itself happens at command entry in an interactive
    # shell, which a sandboxed -c session cannot drive.)
    session server 'echo "size=$HISTSIZE save=$SAVEHIST file=$HISTFILE"
        for o in histignorealldups histsavenodups histfindnodups sharehistory; do [[ -o $o ]] && echo "on:$o"; done'
    assert_empty "$ERR"
    assert_match "$OUT" 'size=10000 save=10000 file=.*/\.zsh_history'
    assert_line "$OUT" on:histignorealldups
    assert_line "$OUT" on:histsavenodups
    assert_line "$OUT" on:histfindnodups
    assert_line "$OUT" on:sharehistory
}

scenario_le_plugins_missing() {
    reset_session; SESSION_TOOLS="starship zoxide carapace eza git"   # no fzf, no plugins
    session server "$LE_KEYS; echo done"
    assert_empty "$ERR"; assert_eq "$CODE" 0
    assert_line "$OUT" "done"
    assert_eq "$(count_matching "$OUT" 'run bootstrap')" 1 'exactly one hint'
    # fallbacks: prefix history search, plain forward-char, stock history search
    assert_line "$OUT" '"^[[A" up-line-or-beginning-search'
    assert_line "$OUT" '"^[[B" down-line-or-beginning-search'
    assert_line "$OUT" '"^F" forward-char'
    assert_line "$OUT" '"^R" history-incremental-search-backward'
    assert_line "$OUT" '"^I" menu-complete'
}

scenario_le_syntax_last() {
    reset_session; SESSION_TOOLS=$LE_ALL_TOOLS; SESSION_PLUGINS=$LE_ALL_PLUGINS
    session devbox 'echo "order=$ORDER"; echo "hl=$ZSH_HIGHLIGHT_HIGHLIGHTERS"'
    assert_empty "$ERR"
    assert_line "$OUT" 'order=zsh-autosuggestions,zsh-history-substring-search,zsh-syntax-highlighting,'
    assert_line "$OUT" 'hl=main'
}

# tests/syntax-colors.txt (shared with Contract.Tests.ps1): every zsh style it
# names holds fg=<its color>, with bright colors as fg=8..fg=15.
scenario_le_syntax_colors() {
    local names=(black red green yellow blue magenta cyan white)
    local rows token color _ps keys key i fg probe=''
    rows=$(tr -d '\r' < "$REPO_ROOT/tests/syntax-colors.txt" | grep -v -e '^#' -e '^$')
    [ -n "$rows" ] || fail 'no rows in syntax-colors.txt'
    while IFS='|' read -r token color _ps keys; do
        for key in ${keys//,/ }; do
            if [ "$key" = ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE ]; then
                probe+="echo \"S:$key=\$$key\"; "
            else
                probe+="echo \"S:$key=\$ZSH_HIGHLIGHT_STYLES[$key]\"; "
            fi
        done
    done <<< "$rows"
    reset_session; SESSION_TOOLS=$LE_ALL_TOOLS; SESSION_PLUGINS=$LE_ALL_PLUGINS
    session devbox "$probe"
    assert_empty "$ERR"
    while IFS='|' read -r token color _ps keys; do
        fg=''
        for i in "${!names[@]}"; do
            [ "$color" = "${names[$i]}" ] && fg=$i
            [ "$color" = "bright-${names[$i]}" ] && fg=$((i + 8))
        done
        case "$fg" in [0-9]*) ;; *) fail "$token: $color is not one of the sixteen" ;; esac
        [ "$fg" -lt 8 ] && fg=${names[$fg]}
        for key in ${keys//,/ }; do
            grep -qE "^S:$key=(.*,)?fg=$fg(,.*)?$" <<< "$OUT" ||
                fail "$token: $key is not fg=$fg; output was: $OUT"
        done
    done <<< "$rows"
}
