# =============================================================================
#  20-completions.zsh
#  Tab completion, mirroring powershell/core/conf.d/20-completions.ps1:
#
#  1. compinit, once per session, with the dump cached: a dump under 24h old is
#     trusted (compinit -C, skips the security scan), an older one is rebuilt
#  2. Carapace    -- covers ~1000 CLIs; its init script is cached by binary mtime
#  3. Native      -- kubectl, helm, gh, docker generate their own zsh completers;
#                    cached by binary mtime, loaded after Carapace so they win
#  4. aws         -- bashcompinit + aws_completer, a live callback with no
#                    startup cost
#
#  A missing tool is skipped silently. A warm cache costs one stat per tool.
#  Cache: $NOWHERE_CACHE_DIR/completions, regenerated when the binary is newer.
# =============================================================================

typeset -g NowhereCompletionDir=$NOWHERE_CACHE_DIR/completions
zmodload zsh/files 2> /dev/null   # builtin mkdir/mv/rm: compinit shells out to them otherwise
mkdir -p $NowhereCompletionDir 2> /dev/null

# --- compinit with a dump cache ---------------------------------------------------
autoload -Uz compinit
typeset -g NowhereCompinitMode=fresh
local _dump=$NowhereCompletionDir/zcompdump
local -a _recent=($_dump(N.mh-24))
if (( $#_recent )); then
    NowhereCompinitMode=cached
    compinit -C -d $_dump
else
    compinit -d $_dump
fi
unset _dump _recent

# Tab opens a selectable menu (Tab/Shift+Tab cycle it; bindings in 10-line-editor.zsh).
zstyle ':completion:*' menu select

# --- Cached generated completer ------------------------------------------------------
#  nowhere_cached_completion <tool> <cache-name> <generator args...>
#  Runs `<tool> <args>` to (re)build the cache when absent or older than the
#  binary, then sources it. Nothing happens if the tool is not installed.
nowhere_cached_completion() {
    local tool=$1 cache=$NowhereCompletionDir/$2 body
    shift 2
    nowhere_tool $tool || return 0
    if [[ ! -s $cache || ! $cache -nt $commands[$tool] ]]; then
        body=$($tool "$@" 2> /dev/null)
        [[ -n $body ]] && print -r -- $body > $cache
    fi
    [[ -s $cache ]] && source $cache
    return 0
}

# --- Carapace, then the native completers (which override it) -------------------------
nowhere_cached_completion carapace carapace-init.zsh _carapace zsh
nowhere_cached_completion kubectl kubectl-completion.zsh completion zsh
nowhere_cached_completion helm    helm-completion.zsh    completion zsh
nowhere_cached_completion gh      gh-completion.zsh      completion -s zsh
nowhere_cached_completion docker  docker-completion.zsh  completion zsh

# --- aws: live callback through bashcompinit ---------------------------------------------
if nowhere_tool aws_completer; then
    autoload -Uz bashcompinit && bashcompinit
    complete -C aws_completer aws
fi
