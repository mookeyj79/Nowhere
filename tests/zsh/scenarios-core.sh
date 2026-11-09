#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for the zsh core layer (ticket #17): environment, aliases, helpers,
# profile commands, goto, venv helpers and cached init. Ids live in tests/scenarios.txt.

# k <name> prints "<name>=<kind>", kind being alias, function, command or none.
KIND_PROBE='k() { if (( $+aliases[$1] )); then echo "$1=alias"; elif (( $+functions[$1] )); then echo "$1=function"; elif (( $+commands[$1] )); then echo "$1=command"; else echo "$1=none"; fi }'

scenario_core_eza_aliases() {
    reset_session; SESSION_TOOLS="eza"
    session server "$KIND_PROBE"'; for n in ls ll la lt llt; do k $n; done; echo "ll=$aliases[ll]"'
    assert_empty "$ERR"
    local n; for n in ls ll la lt llt; do assert_line "$OUT" "$n=alias"; done
    assert_line "$OUT" 'll=eza -l --icons --group-directories-first --git'
    reset_session; SESSION_TOOLS=""
    session server "$KIND_PROBE"'; k ls; k ll'
    assert_empty "$ERR"; assert_line "$OUT" ls=none; assert_line "$OUT" ll=none
}
scenario_core_git_aliases() {
    reset_session; SESSION_TOOLS="git"
    local names='g gst gss ga gaa gc gcmsg gca gco gcb gcm gd gds gp gpf gl gf gb gbd glog gloga grb grbi gsta gstp'
    session server "$KIND_PROBE"'; for n in '"$names"'; do k $n; done'
    assert_empty "$ERR"
    local n; for n in $names; do assert_line "$OUT" "$n=alias"; done
    # flags copied from the PowerShell aliases
    session server 'echo "gpf=$aliases[gpf]"; echo "gloga=$aliases[gloga]"; echo "gf=$aliases[gf]"'
    assert_line "$OUT" 'gpf=git push --force-with-lease'
    assert_line "$OUT" 'gloga=git log --oneline --decorate --graph --all'
    assert_line "$OUT" 'gf=git fetch --all --prune'
}
scenario_core_dot_up() {
    reset_session; SESSION_TOOLS=""
    session server 'echo "up2=$aliases[...]"; echo "up4=$aliases[.....]"'
    assert_empty "$ERR"; assert_line "$OUT" 'up2=cd ../..'; assert_line "$OUT" 'up4=cd ../../../..'
}
scenario_core_bat_fd_debian() {
    # Debian installs bat/fd as batcat/fdfind: alias them when the plain names are absent
    reset_session; SESSION_TOOLS="batcat fdfind"
    session server "$KIND_PROBE"'; k bat; k fd; echo "bat=$aliases[bat]"'
    assert_empty "$ERR"; assert_line "$OUT" bat=alias; assert_line "$OUT" fd=alias
    assert_line "$OUT" 'bat=batcat'
    reset_session; SESSION_TOOLS="bat fd batcat fdfind"
    session server "$KIND_PROBE"'; k bat; k fd'
    assert_line "$OUT" bat=command; assert_line "$OUT" fd=command
    reset_session; SESSION_TOOLS=""
    session server "$KIND_PROBE"'; k bat; k fd'
    assert_empty "$ERR"; assert_line "$OUT" bat=none; assert_line "$OUT" fd=none
}
scenario_core_helpers() {
    reset_session; SESSION_TOOLS="git"; SESSION_REAL="mkdir"
    session server "$KIND_PROBE"'; cd $HOME; for n in gcl mkcd touch wget which; do k $n; done
        mkcd a/b/c; echo "pwd=${PWD#$HOME}"
        cd $HOME; mkdir bar; gcl https://example.com/foo/bar.git; echo "cloned=${PWD#$HOME}"'
    assert_empty "$ERR"
    assert_line "$OUT" gcl=function; assert_line "$OUT" mkcd=function; assert_line "$OUT" wget=function
    assert_line "$OUT" touch=function
    assert_line "$OUT" 'pwd=/a/b/c'
    assert_line "$OUT" 'git clone https://example.com/foo/bar.git'
    assert_line "$OUT" 'cloned=/bar'
    # touch and wget only stand in when the real ones are missing
    reset_session; SESSION_TOOLS="touch wget"
    session server "$KIND_PROBE"'; k touch; k wget'
    assert_line "$OUT" touch=command; assert_line "$OUT" wget=command
}
scenario_core_wget_fallback() {
    reset_session; SESSION_TOOLS="curl"; SESSION_REAL="mkdir"
    session server 'cd $HOME; wget https://example.com/a/file.tgz; wget https://example.com/x -O out.bin -P dl'
    assert_empty "$ERR"
    assert_line "$OUT" 'curl -fL -o file.tgz https://example.com/a/file.tgz'
    assert_line "$OUT" 'curl -fL -o dl/out.bin https://example.com/x'
}
scenario_core_profile_cmds() {
    reset_session; SESSION_TOOLS="nano git"
    session server "$KIND_PROBE"'; for n in reload editp aliases update; do k $n; done
        editp; aliases "gp*"'
    assert_empty "$ERR"
    local n; for n in reload editp aliases update; do assert_line "$OUT" "$n=function"; done
    assert_line "$OUT" "nano $REPO_ROOT"        # editp opens the clone in $EDITOR
    assert_line "$OUT" 'gp -> git push'
    assert_line "$OUT" 'gpf -> git push --force-with-lease'
    assert_no_line "$OUT" 'gst -> git status'
}
scenario_core_reload() {
    reset_session; SESSION_TOOLS="git"
    session server 'unalias gst; reload; echo "gst=${+aliases[gst]}"'
    assert_empty "$ERR"; assert_line "$OUT" gst=1; assert_match "$OUT" 'Reloading'
}
scenario_core_update() {
    reset_session; SESSION_TOOLS=""
    session server 'NowhereProfileDir=$HOME/nowhere-empty; update; echo "code=$?"'
    assert_line "$OUT" code=1; assert_match "$ERR" 'update'
    # with the script present (ticket #19 provides it) update runs it
    reset_session; SESSION_TOOLS=""; SESSION_REAL="mkdir chmod"
    session server 'NowhereProfileDir=$HOME/fake; mkdir -p $NowhereProfileDir/core/bin; f=$NowhereProfileDir/core/bin/update
        print "#!/bin/sh\necho updated \$*" > $f; command chmod +x $f; update --now'
    assert_line "$OUT" 'updated --now'
}
scenario_core_goto() {
    reset_session; SESSION_TOOLS=""; SESSION_REAL="mkdir"
    SESSION_LOCAL='typeset -A NowhereGotoBookmarks=(lab "$HOME/lab")'
    session server 'mkdir -p $HOME/projects $HOME/lab; goto; goto pr; echo "at=${PWD#$HOME}"; goto lab; echo "at=${PWD#$HOME}"
        goto nope; echo "code=$?"; echo "at=${PWD#$HOME}"'
    assert_match "$OUT" '^dl  '; assert_match "$OUT" '^pr  '; assert_match "$OUT" '^lab  '
    assert_line "$OUT" at=/projects; assert_line "$OUT" at=/lab; assert_line "$OUT" code=1
    assert_match "$ERR" "Bookmark 'nope' not found"
}
scenario_core_venv() {
    reset_session; SESSION_TOOLS="uv"; SESSION_REAL="mkdir"
    session server "$KIND_PROBE"'; for n in mkvirtualenv workon rmvirtualenv lsvirtualenv cdvirtualenv seedvenv pipinstall activate; do k $n; done
        echo "home=$WORKON_HOME"; mkvirtualenv demo 3.12; mkdir -p $WORKON_HOME/demo/bin; seedvenv demo; pipinstall -e demo requests; pipinstall'
    assert_match "$OUT" 'home=.*/\.venvs'
    local n; for n in mkvirtualenv workon rmvirtualenv lsvirtualenv cdvirtualenv seedvenv pipinstall activate; do assert_line "$OUT" "$n=function"; done
    assert_match "$OUT" 'venv .*/\.venvs/demo --python 3.12'
    assert_match "$OUT" 'pip install pip --python .*/\.venvs/demo'
    assert_match "$OUT" 'pip install --python .*/\.venvs/demo requests'
    assert_match "$ERR" 'Usage: pipinstall'
}
scenario_core_venv_activate() {
    reset_session; SESSION_TOOLS=""; SESSION_REAL="mkdir rm"
    session server 'mkdir -p $WORKON_HOME/demo/bin $WORKON_HOME/other/bin
        print "export DEMO_ACTIVE=1; export VIRTUAL_ENV=\$WORKON_HOME/demo" > $WORKON_HOME/demo/bin/activate
        lsvirtualenv; workon demo; echo "active=$DEMO_ACTIVE"; cdvirtualenv; echo "at=${PWD:t}"
        workon missing; echo "code=$?"; rmvirtualenv other; echo "left=$(lsvirtualenv)"'
    assert_line "$OUT" demo; assert_line "$OUT" other; assert_line "$OUT" active=1; assert_line "$OUT" at=demo
    assert_line "$OUT" code=1; assert_match "$ERR" "virtualenv 'missing' not found"
    assert_no_line "$OUT" 'left=other'
}
scenario_core_env() {
    reset_session; SESSION_TOOLS=""
    session server 'echo "pager=$PAGER"; echo "less=$LESS"; echo "editor=$EDITOR"; echo "visual=$VISUAL"'
    assert_line "$OUT" pager=less; assert_line "$OUT" 'less=-R -F -X'; assert_line "$OUT" editor=nano; assert_line "$OUT" visual=nano
    reset_session; SESSION_TOOLS=""; SESSION_LOCAL='NowhereEditor=vim'
    session devbox 'echo "editor=$EDITOR"'
    assert_line "$OUT" editor=vim
}
scenario_core_init_cache() {
    reset_session; SESSION_TOOLS="starship zoxide"; SESSION_REAL="mkdir"
    session server 'echo "cfg=$STARSHIP_CONFIG"; echo "cache=$NOWHERE_CACHE_DIR"
        print "zoxide: $(<$NOWHERE_CACHE_DIR/zoxide-init.zsh)"; print "starship: $(<$NOWHERE_CACHE_DIR/starship-init.zsh)"'
    assert_empty "$ERR"
    assert_line "$OUT" "cfg=$REPO_ROOT/shared/starship.toml"
    assert_match "$OUT" 'cache=.*/xdg/nowhere'
    assert_line "$OUT" 'zoxide: zoxide init zsh --cmd cd'
    assert_line "$OUT" 'starship: starship init zsh'
    # the cached scripts are what gets sourced (the stub prints its own arguments)
    assert_line "$OUT" 'zoxide init zsh --cmd cd'
    assert_line "$OUT" 'starship init zsh'
}
scenario_core_init_regen() {
    # a cache newer than the binary is reused; a binary newer than the cache regenerates it
    reset_session; SESSION_TOOLS="starship zoxide"; SESSION_REAL="mkdir touch"
    session server 'c=$NOWHERE_CACHE_DIR/starship-init.zsh; b=${commands[starship]:A}
        touch -d "2000-01-01" $b; print -r "echo warm" > $c
        source $HOME/stub.zsh > /dev/null; echo "old-bin: $(<$c)"
        touch -d "2099-01-01" $b
        source $HOME/stub.zsh > /dev/null; echo "new-bin: $(<$c)"'
    assert_empty "$ERR"
    assert_line "$OUT" 'old-bin: echo warm'
    assert_line "$OUT" 'new-bin: starship init zsh'
}
# A generator shim for core-init-rules: quiet prints nothing; broken prints a
# script but exits 1. Both log each run to gen.log.
init_rules_shim() {
    case $2 in
        quiet) printf '#!/bin/sh\necho quiet >> "%s/gen.log"\n' "$3" > "$1" ;;
        broken) printf '#!/bin/sh\necho broken >> "%s/gen.log"\necho BROKEN=1\nexit 1\n' "$3" > "$1" ;;
    esac
}
scenario_core_init_rules() {
    # empty output is cached and not regenerated; a failing generator caches
    # and sources nothing, and is retried next time
    reset_session; SESSION_TOOLS="quiet broken"; SESSION_SHIM=init_rules_shim; SESSION_REAL="touch"
    session server 'touch -d "2000-01-01" ${commands[quiet]:A} ${commands[broken]:A}
        repeat 2 { nowhere_cached_init quiet-init quiet; nowhere_cached_init broken-init broken }
        [[ -e $NOWHERE_CACHE_DIR/quiet-init.zsh ]] && echo quiet=cached
        [[ -e $NOWHERE_CACHE_DIR/broken-init.zsh ]] || echo broken=uncached
        echo "sourced=[$BROKEN]"'
    assert_empty "$ERR"
    assert_line "$OUT" quiet=cached; assert_line "$OUT" broken=uncached; assert_line "$OUT" 'sourced=[]'
    local log; log=$(cat "$SESSION_SB/gen.log")
    assert_eq "$(count_matching "$log" quiet)" 1 'quiet generated once'
    assert_eq "$(count_matching "$log" broken)" 2 'broken retried'
}
scenario_core_init_absent() {
    reset_session; SESSION_TOOLS=""
    session server 'echo "cfg=[$STARSHIP_CONFIG]"; echo "cdi=${+functions[cdi]}"'
    assert_empty "$ERR"; assert_line "$OUT" 'cfg=[]'; assert_line "$OUT" cdi=0
}
