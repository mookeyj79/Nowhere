# =============================================================================
#  profile.zsh  --  Nowhere ZSH entry point
#
#  Reached through a few-line stub at ~/.zshrc that sets NOWHERE_ROLE
#  (devbox | server) and sources this file from the clone.
#
#  Order: local override first (~/.config/nowhere/local.zsh), then core/conf.d
#  merged with dev/conf.d (devbox only) in one filename order. Every value the
#  override can set is read with a default, so a missing override still works.
# =============================================================================

typeset -g NowhereProfileDir=${${(%):-%x}:A:h}
typeset -g NowhereRepoDir=${NowhereProfileDir:h}
typeset -g NowhereRole=server
[[ $NOWHERE_ROLE == devbox ]] && NowhereRole=devbox

# --- Local override -----------------------------------------------------------
[[ -r $HOME/.config/nowhere/local.zsh ]] && source $HOME/.config/nowhere/local.zsh

export NOWHERE_HOME=${NOWHERE_HOME:-$NowhereRepoDir}

# --- Layers -------------------------------------------------------------------
local _layers=(core)
[[ $NowhereRole == devbox ]] && _layers+=(dev)

local _layer _file _entry
local -a _entries=()
for _layer in $_layers; do
    [[ -d $NowhereProfileDir/$_layer/bin ]] && path=($NowhereProfileDir/$_layer/bin $path)
    for _file in $NowhereProfileDir/$_layer/conf.d/*.zsh(N); do
        _entries+=("${_file:t}|$_file")    # sort key is the bare filename
    done
done
for _entry in ${(o)_entries}; do
    source ${_entry#*|}
done

# --- The one hint --------------------------------------------------------------
nowhere_hint_flush

unset _layers _layer _file _entry _entries
