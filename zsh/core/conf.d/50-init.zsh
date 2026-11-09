# =============================================================================
#  50-init.zsh
#  Zoxide (smart cd) and Starship (prompt). Must be last: Starship sets the
#  prompt hooks and needs to see all env vars already set.
#
#  Both init scripts are cached by nowhere_cached_init (00-environment.zsh),
#  so a warm start spawns neither.
# =============================================================================

# --- zoxide (frecency-based smart cd) ---------------------------------------------
#  --cmd cd takes over the cd verb so muscle memory works unchanged; `cdi` is
#  the interactive picker.
nowhere_cached_init zoxide-init zoxide init zsh --cmd cd

# --- Starship ------------------------------------------------------------------------
#  Config: the single shared shared/starship.toml in the clone.
if nowhere_tool starship; then
    [[ -r $NowhereRepoDir/shared/starship.toml ]] && export STARSHIP_CONFIG=$NowhereRepoDir/shared/starship.toml
    nowhere_cached_init starship-init starship init zsh
fi

# The one bootstrap hint is printed by profile.zsh after the last file.
