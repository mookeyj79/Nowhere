# =============================================================================
#  01-dev-environment.zsh  (dev layer: devbox only)
#  Dev-machine defaults; local.zsh values still win.
# =============================================================================

[[ -z $NowhereEditor ]] && export EDITOR='code --wait'
export VISUAL=$EDITOR
