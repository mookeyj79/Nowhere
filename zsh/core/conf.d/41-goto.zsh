# =============================================================================
#  41-goto.zsh
#  Goto bookmarks (extend or override with an associative array
#  NowhereGotoBookmarks in local.zsh)
#  Usage: goto pr   -> cd ~/projects
#         goto      -> list all bookmarks
# =============================================================================

typeset -gA _NowhereGoto=(
    pr   $HOME/projects
    dot  $HOME/.config
    zsh  $NowhereProfileDir
    dl   $HOME/Downloads
)
if [[ ${(t)NowhereGotoBookmarks} == association* ]]; then
    _NowhereGoto+=("${(kv@)NowhereGotoBookmarks}")
fi

goto() {
    local name=$1 k
    if [[ -z $name ]]; then
        for k in ${(ko)_NowhereGoto}; do print -r -- "${(r:8:)k}$_NowhereGoto[$k]"; done
        return
    fi
    if [[ -n $_NowhereGoto[$name] && -d $_NowhereGoto[$name] ]]; then
        cd -- $_NowhereGoto[$name]
    else
        print -u2 "Bookmark '$name' not found. Run 'goto' to list all."
        return 1
    fi
}

_nowhere_goto() { compadd -- ${(ko)_NowhereGoto} }
(( $+functions[compdef] )) && compdef _nowhere_goto goto
