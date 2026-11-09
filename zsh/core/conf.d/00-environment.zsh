# =============================================================================
#  00-environment.zsh
#  Env vars, tool/plugin presence helpers, the cached-init helper and the
#  one-per-session hint. Runs first so every later file sees them.
#
#  The profile never installs anything: a missing tool or plugin is skipped
#  silently and profile.zsh prints at most one "run bootstrap" hint per session.
# =============================================================================

# --- Tool presence --------------------------------------------------------------
nowhere_tool() { (( $+commands[$1] )) }
# The tools whose absence triggers the hint: shared/core-tools.txt, one per
# line, comments dropped. $(<file) reads it without forking.
typeset -ga NowhereCoreTools=(${${(f)"$(<$NowhereRepoDir/shared/core-tools.txt)"}:#\#*})
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

# --- Cached init ------------------------------------------------------------------
#  nowhere_cached_init <name> <tool> [args...]  source a cached copy of what
#  `<tool> [args...]` prints (an init or completion script), so a warm start
#  spawns nothing. The same rules as Get-NowhereCachedInit in 00-environment.ps1:
#    - the cache is $NOWHERE_CACHE_DIR/<name>.zsh
#    - it is fresh while it is newer than the tool's binary, else regenerated
#    - empty output is cached too, so it is not regenerated on every start
#    - an absent tool, a failing generator or an unwritable cache directory
#      sources nothing and prints nothing
nowhere_cached_init() {
    local bin=$commands[$2] file=$NOWHERE_CACHE_DIR/$1.zsh out
    shift 2
    [[ -n $bin ]] || return 0
    if [[ ! -e $file || ! $file -nt $bin ]]; then
        out=$($bin "$@" 2> /dev/null) || return 0
        [[ -d $NOWHERE_CACHE_DIR ]] || mkdir -p -- $NOWHERE_CACHE_DIR 2> /dev/null || return 0
        { print -r -- $out >| $file } 2> /dev/null || return 0
    fi
    source $file
    return 0
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
