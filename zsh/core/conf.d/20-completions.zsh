# =============================================================================
#  20-completions.zsh
#  Tab completion, mirroring powershell/core/conf.d/20-completions.ps1:
#
#  1. compinit, once per session, with the dump cached: a dump under 24h old is
#     trusted (compinit -C, skips the security scan), an older one is rebuilt
#  2. Carapace    -- covers ~1000 CLIs; its init script is cached (nowhere_cached_init)
#  3. Native      -- kubectl, helm, gh, docker generate their own zsh completers;
#                    cached by binary mtime, loaded after Carapace so they win
#  4. aws         -- bashcompinit + aws_completer, a live callback with no
#                    startup cost
#
#  A missing tool is skipped silently. A warm cache costs one stat per tool.
#  Generated scripts: $NOWHERE_CACHE_DIR/<name>.zsh; the compinit dump:
#  $NOWHERE_CACHE_DIR/completions.
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

# --- Carapace, then the native completers (which override it) -------------------------
#  Each generated script is cached by nowhere_cached_init (00-environment.zsh).
nowhere_cached_init carapace-init      carapace _carapace zsh
nowhere_cached_init kubectl-completion kubectl  completion zsh
nowhere_cached_init helm-completion    helm     completion zsh
nowhere_cached_init gh-completion      gh       completion -s zsh
nowhere_cached_init docker-completion  docker   completion zsh

# --- aws: live callback through bashcompinit ---------------------------------------------
if nowhere_tool aws_completer; then
    autoload -Uz bashcompinit && bashcompinit
    complete -C aws_completer aws
fi
