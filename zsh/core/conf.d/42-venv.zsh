# =============================================================================
#  42-venv.zsh
#  Virtualenv helpers: uv-backed, virtualenvwrapper-style. Named envs live in
#  $WORKON_HOME (~/.venvs); project-local envs (uv venv) use `activate`.
# =============================================================================

mkvirtualenv() {
    [[ -n $1 ]] || { print -u2 'Usage: mkvirtualenv <name> [python-version]'; return 1 }
    local target=$WORKON_HOME/$1
    uv venv $target ${2:+--python $2} || return
    [[ -r $target/bin/activate ]] && source $target/bin/activate
}

workon() {
    [[ -n $1 ]] || { lsvirtualenv; return }
    if [[ -r $WORKON_HOME/$1/bin/activate ]]; then
        source $WORKON_HOME/$1/bin/activate
    else
        print -u2 "virtualenv '$1' not found. Run 'workon' to list."
        return 1
    fi
}

rmvirtualenv() {
    [[ -n $1 ]] || { print -u2 'Usage: rmvirtualenv <name>'; return 1 }
    local target=$WORKON_HOME/$1
    if [[ ! -d $target ]]; then print -u2 "virtualenv '$1' not found."; return 1; fi
    [[ $VIRTUAL_ENV == $target ]] && (( $+functions[deactivate] )) && deactivate
    rm -rf -- $target
    print -P "%F{yellow}Removed virtualenv '$1'.%f"
}

lsvirtualenv() {
    print -P '%F{cyan}Available virtualenvs:%f'
    if [[ -d $WORKON_HOME ]]; then
        local d; for d in $WORKON_HOME/*(N/); do print -r -- ${d:t}; done
    else
        print '  (none)'
    fi
}

cdvirtualenv() {
    [[ -n $VIRTUAL_ENV ]] || { print -u2 'No virtualenv is currently active.'; return 1 }
    cd -- $VIRTUAL_ENV
}

#  Seed pip into a named or the active virtualenv (uv venvs ship without pip)
seedvenv() {
    if [[ -n $1 ]]; then
        [[ -d $WORKON_HOME/$1/bin ]] || { print -u2 "virtualenv '$1' not found. Run 'lsvirtualenv' to list available."; return 1 }
        print -P "%F{cyan}  -> Seeding pip into '$1'%f"
        uv pip install pip --python $WORKON_HOME/$1
    elif [[ -n $VIRTUAL_ENV ]]; then
        print -P "%F{cyan}  -> Seeding pip into '${VIRTUAL_ENV:t}'%f"
        uv pip install pip
    else
        print -u2 "No virtualenv active and no name specified. Run 'workon <env>' first or pass a name."
        return 1
    fi
}

#  pipinstall [-e env] <package>...  install into a named or the active virtualenv
pipinstall() {
    local env
    if [[ $1 == -e ]]; then env=$2; shift 2; fi
    (( $# )) || { print -u2 'Usage: pipinstall [-e <name>] <package> [package...]'; return 1 }
    if [[ -n $env ]]; then
        [[ -d $WORKON_HOME/$env/bin ]] || { print -u2 "virtualenv '$env' not found. Run 'lsvirtualenv' to list available."; return 1 }
        print -P "%F{cyan}  -> $env%f"
        uv pip install --python $WORKON_HOME/$env "$@"
    elif [[ -n $VIRTUAL_ENV ]]; then
        print -P "%F{cyan}  -> ${VIRTUAL_ENV:t}%f"
        uv pip install "$@"
    else
        print -u2 "No virtualenv active and no -e specified. Run 'workon <env>' first or use -e <name>."
        return 1
    fi
}

#  activate [dir]  project-local .venv dirs (created with `uv venv`); no arg lists them
activate() {
    if [[ -z $1 ]]; then
        local d; for d in *(N/); do [[ -r $d/bin/activate ]] && print -r -- $d; done
        return
    fi
    if [[ -r $1/bin/activate ]]; then
        source $1/bin/activate
    else
        print -u2 "No virtual environment '$1' found in current directory."
        return 1
    fi
}

#  Complete env names for the named-env helpers
_nowhere_venvs() { compadd -- $WORKON_HOME/*(N/:t) }
if (( $+functions[compdef] )); then
    compdef _nowhere_venvs workon rmvirtualenv seedvenv
fi
