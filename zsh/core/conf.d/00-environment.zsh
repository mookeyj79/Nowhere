# =============================================================================
#  00-environment.zsh
#  Env vars, tool/plugin presence helpers and the one-per-session hint. Runs
#  first so every later file sees them.
#
#  The profile never installs anything: a missing tool or plugin is skipped
#  silently and profile.zsh prints at most one "run bootstrap" hint per session.
# =============================================================================

# --- Tool presence --------------------------------------------------------------
nowhere_tool() { (( $+commands[$1] )) }
typeset -ga NowhereCoreTools=(starship zoxide carapace fzf eza git)
typeset -ga NowhereMissing=()

# --- Plugin directory convention --------------------------------------------------
#  Plugins live at $NowhereDataDir/plugins/<name>, cloned at a pinned SHA by
#  bootstrap.sh (zsh/plugins.json). nowhere_plugin <name> <file-in-plugin>
#  sources the file if present and otherwise skips it, remembering the gap.
typeset -g NowhereDataDir=${NOWHERE_DATA_DIR:-$HOME/.local/share/nowhere}
nowhere_plugin() {
    local file=$NowhereDataDir/plugins/$1/$2
    if [[ -r $file ]]; then
        source $file
    else
        NowhereMissing+=("plugin:$1")
        return 1
    fi
}

# --- The hint -----------------------------------------------------------------------
typeset -g NowhereHintShown=0
nowhere_hint_flush() {
    local t
    for t in $NowhereCoreTools; do nowhere_tool $t || NowhereMissing+=("tool:$t"); done
    if (( ! NowhereHintShown && $#NowhereMissing )); then
        NowhereHintShown=1
        print -r -- "nowhere: some tools or plugins are missing; run bootstrap to install them."
    fi
}

# --- Editor ---------------------------------------------------------------------------
#  nano by default (the dev layer switches to 'code --wait'); local.zsh can set NowhereEditor
export EDITOR=${NowhereEditor:-nano}
export VISUAL=$EDITOR

# --- Pager ----------------------------------------------------------------------------
export PAGER=less
export LESS='-R -F -X'   # -R color passthrough, -F quit if one screen, -X no init

# Central virtualenv store, same convention as the PowerShell profile
export WORKON_HOME=$HOME/.venvs

# Cache for generated init scripts and completions
export NOWHERE_CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/nowhere

# Local bin (uv and the pinned gitleaks land here)
[[ -d $HOME/.local/bin ]] && path=($HOME/.local/bin $path)
