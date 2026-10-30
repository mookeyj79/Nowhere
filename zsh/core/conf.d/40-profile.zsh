# =============================================================================
#  40-profile.zsh
#  Profile management: reload, edit, update, show aliases.
# =============================================================================

reload() {
    print -P '%F{cyan}Reloading profile...%f'
    source $NowhereProfileDir/profile.zsh
}

editp() { ${=EDITOR} $NowhereRepoDir }

#  aliases [glob]  list aliases whose name matches the glob
aliases() {
    local k
    for k in ${(ko)aliases}; do
        [[ $k == ${~${1:-*}} ]] && print -r -- "$k -> $aliases[$k]"
    done
}

#  update is the script in core/bin (shared name with PowerShell's `update`)
update() {
    local script=$NowhereProfileDir/core/bin/update
    if [[ -x $script ]]; then
        $script "$@"
    else
        print -u2 "update: $script not found"
        return 1
    fi
}
