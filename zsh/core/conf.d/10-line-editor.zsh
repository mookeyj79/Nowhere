# =============================================================================
#  10-line-editor.zsh
#  History, key bindings, ghost-text suggestions and fzf shell integration.
#  Counterpart of powershell/core/conf.d/10-line-editor.ps1.
#
#  Plugins are sourced behind existence checks (nowhere_plugin); when one is
#  missing its binding falls back to a stock zsh widget. Syntax highlighting
#  is not loaded here: 90-syntax-highlighting must load last.
# =============================================================================

# --- History ------------------------------------------------------------------
typeset -g HISTFILE=${HISTFILE:-$HOME/.zsh_history}
typeset -g HISTSIZE=10000
typeset -g SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS HIST_FIND_NO_DUPS   # no duplicates
setopt HIST_IGNORE_SPACE SHARE_HISTORY                           # share across sessions

# --- Editing ------------------------------------------------------------------
bindkey -e                       # Emacs mode
unsetopt BEEP

# --- Plugins ------------------------------------------------------------------
local _suggest=0 _search=0
nowhere_plugin zsh-autosuggestions zsh-autosuggestions.zsh && _suggest=1
nowhere_plugin zsh-history-substring-search zsh-history-substring-search.zsh && _search=1

# Ghost text: one grey suggestion from history (Overlay1, as in the PSReadLine config)
typeset -g ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#8087a2'
typeset -ga ZSH_AUTOSUGGEST_STRATEGY=(history)

# --- Key bindings -------------------------------------------------------------
bindkey '^I'   menu-complete             # Tab: menu
bindkey '^[[Z' reverse-menu-complete     # Shift+Tab: reverse cycle

# Up/Down: prefix-filtered history search
local _up=up-line-or-beginning-search _down=down-line-or-beginning-search
if (( _search )); then
    _up=history-substring-search-up; _down=history-substring-search-down
else
    autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
    zle -N up-line-or-beginning-search 2> /dev/null
    zle -N down-line-or-beginning-search 2> /dev/null
fi
bindkey '^[[A' $_up;   bindkey '^[OA' $_up
bindkey '^[[B' $_down; bindkey '^[OB' $_down
[[ -n ${terminfo[kcuu1]-} ]] && bindkey ${terminfo[kcuu1]} $_up
[[ -n ${terminfo[kcud1]-} ]] && bindkey ${terminfo[kcud1]} $_down

# Ctrl+f accepts the whole suggestion; Alt+f is forward-word, which the plugin
# treats as accept-one-word (its default partial-accept widget).
(( _suggest )) && bindkey '^F' autosuggest-accept
bindkey '^[f' forward-word

# --- fzf: Ctrl+r history, Ctrl+t files, Alt+c cd ---------------------------------
#  'fzf --zsh' needs fzf 0.48+; older packages (Debian) ship key-bindings.zsh.
if nowhere_tool fzf; then
    local _fzf_init
    _fzf_init=$(fzf --zsh 2> /dev/null)
    if [[ -n $_fzf_init ]]; then
        eval "$_fzf_init"
    elif [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
        source /usr/share/doc/fzf/examples/key-bindings.zsh
    fi
fi
unset _suggest _search _up _down _fzf_init
