# =============================================================================
#  90-syntax-highlighting.zsh
#  Loads after 50-init, as zsh-syntax-highlighting requires. A missing plugin
#  is skipped (see nowhere_plugin in 00-environment).
#
#  Colors are the terminal's own sixteen, by name, so the command line follows
#  the terminal's theme. Only the styles that PSReadLine also colors are set,
#  with the same color as there (tests/syntax-colors.txt); the rest keep the
#  plugin's defaults. A theme file (~/.config/nowhere/theme.zsh) loads after
#  this one and can change any of them.
# =============================================================================

#  Command-line colouring only (the 'main' highlighter): the cheapest one.
#  Autosuggestions and history-substring-search are sourced earlier in
#  10-line-editor.
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main)

typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES+=(
    arg0                          'fg=blue'             # commands, aliases, functions
    precommand                    'fg=blue,underline'   # sudo, noglob, ...
    single-quoted-argument        'fg=green'
    double-quoted-argument        'fg=green'
    dollar-quoted-argument        'fg=green'
    comment                       'fg=8'                # bright black
    reserved-word                 'fg=magenta'          # if, for, function, ...
    dollar-double-quoted-argument 'fg=cyan'             # $var inside "..."
    unknown-token                 'fg=red,bold'
)

nowhere_plugin zsh-syntax-highlighting zsh-syntax-highlighting.zsh
true
