# =============================================================================
#  50-init.zsh
#  Zoxide (smart cd) and Starship (prompt). Must be last: Starship sets the
#  prompt hooks and needs to see all env vars already set.
#
#  Both init scripts are cached under $NOWHERE_CACHE_DIR and regenerated only
#  when the binary is newer than the cache, so a warm start spawns neither.
# =============================================================================

#  _nowhere_cached_init <name> <command> [args...]  source the cached output of
#  `<command> [args...]`, regenerating the cache when the binary is newer.
_nowhere_cached_init() {
    local name=$1 bin=$commands[$2] file=$NOWHERE_CACHE_DIR/$1-init.zsh out
    shift
    [[ -n $bin ]] || return 0
    if [[ ! -s $file || $bin -nt $file ]]; then
        out=$("$@") || return 0
        if [[ ! -d $NOWHERE_CACHE_DIR ]] && (( $+commands[mkdir] )); then
            mkdir -p -- $NOWHERE_CACHE_DIR
        fi
        if [[ -d $NOWHERE_CACHE_DIR ]]; then
            print -r -- $out >| $file
        else
            eval "$out"    # no cache directory available: run uncached
            return 0
        fi
    fi
    [[ -r $file ]] && source $file
    return 0
}

# --- zoxide (frecency-based smart cd) ---------------------------------------------
#  --cmd cd takes over the cd verb so muscle memory works unchanged; `cdi` is
#  the interactive picker.
_nowhere_cached_init zoxide zoxide init zsh --cmd cd

# --- Starship ------------------------------------------------------------------------
#  Config: the single shared shared/starship.toml in the clone.
if nowhere_tool starship; then
    [[ -r $NowhereRepoDir/shared/starship.toml ]] && export STARSHIP_CONFIG=$NowhereRepoDir/shared/starship.toml
    _nowhere_cached_init starship starship init zsh
fi

# The one bootstrap hint is printed by profile.zsh after the last file.
