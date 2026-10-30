# =============================================================================
#  90-syntax-highlighting.zsh
#  Loads after 50-init, as zsh-syntax-highlighting requires. The Catppuccin
#  Macchiato theme must be sourced before the plugin. Missing plugins are
#  skipped (see nowhere_plugin in 00-environment).
# =============================================================================

nowhere_plugin catppuccin-zsh-syntax-highlighting themes/catppuccin_macchiato-zsh-syntax-highlighting.zsh
nowhere_plugin zsh-syntax-highlighting zsh-syntax-highlighting.zsh
true
