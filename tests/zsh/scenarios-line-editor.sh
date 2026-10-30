#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for zsh/core/conf.d/10-line-editor.zsh and 90-syntax-highlighting.zsh
# (ticket #15). Sourced by run.sh; ids and pwsh counterparts live in tests/scenarios.txt.

LE_ALL_PLUGINS="zsh-autosuggestions:zsh-autosuggestions.zsh:AS_LOADED zsh-history-substring-search:zsh-history-substring-search.zsh:HS_LOADED catppuccin-zsh-syntax-highlighting:themes/catppuccin_macchiato-zsh-syntax-highlighting.zsh:THEME_LOADED zsh-syntax-highlighting:zsh-syntax-highlighting.zsh:SYNTAX_LOADED"
LE_ALL_TOOLS="starship zoxide carapace fzf eza git"
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
    assert_line "$OUT" 'style=fg=#8087a2'
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
    assert_line "$OUT" 'order=zsh-autosuggestions,zsh-history-substring-search,catppuccin-zsh-syntax-highlighting,zsh-syntax-highlighting,'
    assert_line "$OUT" 'hl=main'
}
