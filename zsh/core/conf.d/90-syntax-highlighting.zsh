# =============================================================================
#  90-syntax-highlighting.zsh
#  Loads after 50-init, as zsh-syntax-highlighting requires. The Catppuccin
#  Macchiato theme must be sourced before the plugin. Missing plugins are
#  skipped (see nowhere_plugin in 00-environment).
# =============================================================================

#  Command-line colouring only (the 'main' highlighter): cheapest, and all the
#  Macchiato theme styles. Autosuggestions and history-substring-search are
#  sourced earlier in 10-line-editor.
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)

nowhere_plugin catppuccin-zsh-syntax-highlighting themes/catppuccin_macchiato-zsh-syntax-highlighting.zsh
nowhere_plugin zsh-syntax-highlighting zsh-syntax-highlighting.zsh
true
