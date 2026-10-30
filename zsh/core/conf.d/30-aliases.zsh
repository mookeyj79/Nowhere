# =============================================================================
#  30-aliases.zsh
#  One-liner aliases, each group guarded by tool presence. One-liners only;
#  anything with logic lives in 35-helpers. Git aliases are hand-copied from
#  powershell/core/conf.d/30-aliases.ps1 so the flags match.
# =============================================================================

# --- Git ------------------------------------------------------------------------
if nowhere_tool git; then
    alias g='git'
    alias gst='git status'
    alias gss='git status -s'
    alias ga='git add'
    alias gaa='git add --all'
    alias gc='git commit -v'
    alias gcmsg='git commit -m'
    alias gca='git commit -v --amend'
    alias gco='git checkout'
    alias gcb='git checkout -b'
    alias gcm='git checkout main'
    alias gd='git diff'
    alias gds='git diff --staged'
    alias gp='git push'
    alias gpf='git push --force-with-lease'
    alias gl='git pull'
    alias gf='git fetch --all --prune'
    alias gb='git branch'
    alias gbd='git branch -d'
    alias glog='git log --oneline --decorate --graph'
    alias gloga='git log --oneline --decorate --graph --all'
    alias grb='git rebase'
    alias grbi='git rebase -i'
    alias gsta='git stash push'
    alias gstp='git stash pop'
fi

# --- Navigation -------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# --- eza (replaces ls; icons and git status built in) ---------------------------
if nowhere_tool eza; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -l --icons --group-directories-first --git'
    alias la='eza -la --icons --group-directories-first --git'
    alias lt='eza --tree --icons --level=2'
    alias llt='eza -l --tree --icons --level=2 --git'
fi

# --- Debian names -----------------------------------------------------------------
#  apt installs bat as batcat and fd as fdfind; keep the upstream names working.
nowhere_tool bat || { nowhere_tool batcat && alias bat='batcat'; }
nowhere_tool fd || { nowhere_tool fdfind && alias fd='fdfind'; }
