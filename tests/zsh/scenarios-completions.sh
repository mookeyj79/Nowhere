#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for zsh/core/conf.d/20-completions.zsh (ids in scenarios-completions.txt).
# Completion tools are faked: each shim logs its argv to gen.log and prints a tiny
# completion script that marks itself loaded (and appends to ORDER).

# A completion-generator shim (SESSION_SHIM): logs its argv to gen.log and
# prints a completion script that marks itself loaded.
cs_shim() {
    local path=$1 t=$2 log=$3/gen.log
    case $t in
        aws | aws_completer) printf '#!/bin/sh\n:\n' > "$path" ;;
        carapace) printf '#!/bin/sh\necho "carapace $*" >> "%s"\necho "ORDER=\\"\\${ORDER}carapace,\\""\n' "$log" > "$path" ;;
        *) printf '#!/bin/sh\necho "%s $*" >> "%s"\necho "LOADED_%s=1; ORDER=\\"\\${ORDER}%s,\\""\n' "$t" "$log" "$t" "$t" > "$path" ;;
    esac
}
# csession <probe> [sandbox to reuse]: a server session with CS_TOOLS as
# completion shims; reusing a sandbox keeps its cache. Sets CS_SB OUT ERR CODE.
csession() {
    reset_session; SESSION_TOOLS=${CS_TOOLS:-}; SESSION_SHIM=cs_shim; SESSION_REUSE=${2:-}
    session server "$1"; CS_SB=$SESSION_SB
}
cs_gen_log() { cat "$CS_SB/gen.log" 2> /dev/null || true; }
cs_gen_count() { cs_gen_log | wc -l | tr -d ' '; }
CS_CACHE=xdg/nowhere            # generated scripts (nowhere_cached_init)
CS_DUMP=xdg/nowhere/completions # the compinit dump

scenario_completions_compinit() {
    CS_TOOLS=""
    csession 'echo "compdef=${+functions[compdef]}"; echo "mode=$NowhereCompinitMode"'
    assert_line "$OUT" compdef=1; assert_line "$OUT" mode=fresh; assert_empty "$ERR"
    assert_file "$CS_SB/$CS_DUMP/zcompdump"
}
scenario_completions_menu_select() {
    CS_TOOLS=""
    csession 'zstyle -s ":completion:*" menu m; echo "menu=$m"; bindkey "^I"; bindkey "^[[Z"'
    assert_empty "$ERR"
    assert_line "$OUT" 'menu=select'
    assert_line "$OUT" '"^I" menu-complete'
    assert_line "$OUT" '"^[[Z" reverse-menu-complete'
}
scenario_completions_dump_cache() {
    CS_TOOLS=""
    csession ':'
    csession 'echo "mode=$NowhereCompinitMode"' "$CS_SB"
    assert_line "$OUT" mode=cached
    touch -d '2 days ago' "$CS_SB/$CS_DUMP/zcompdump"
    csession 'echo "mode=$NowhereCompinitMode"' "$CS_SB"
    assert_line "$OUT" mode=fresh
}
scenario_completions_native_cached() {
    CS_TOOLS="kubectl helm gh docker"
    local probe='echo "k=$LOADED_kubectl h=$LOADED_helm g=$LOADED_gh d=$LOADED_docker"'
    csession "$probe"
    assert_line "$OUT" 'k=1 h=1 g=1 d=1'; assert_empty "$ERR"
    local log; log=$(cs_gen_log)
    assert_line "$log" 'kubectl completion zsh'; assert_line "$log" 'helm completion zsh'
    assert_line "$log" 'gh completion -s zsh'; assert_line "$log" 'docker completion zsh'
    csession "$probe" "$CS_SB"
    assert_line "$OUT" 'k=1 h=1 g=1 d=1'
    assert_eq "$(cs_gen_count)" 4 "second session must not regenerate"
}
scenario_completions_regen_newer() {
    CS_TOOLS="kubectl"
    csession ':'
    touch -d '1 minute ago' "$CS_SB/$CS_CACHE/kubectl-completion.zsh"
    touch -d '1 hour ago' "$CS_SB/bin/kubectl"
    csession ':' "$CS_SB"
    assert_eq "$(cs_gen_count)" 1 "older binary keeps the cache"
    touch -d '1 second ago' "$CS_SB/bin/kubectl"
    touch -d '1 hour ago' "$CS_SB/$CS_CACHE/kubectl-completion.zsh"
    csession 'echo "k=$LOADED_kubectl"' "$CS_SB"
    assert_eq "$(cs_gen_count)" 2 "newer binary regenerates"
    assert_line "$OUT" k=1
}
scenario_completions_carapace() {
    CS_TOOLS="carapace kubectl"
    csession 'echo "order=$ORDER"'
    assert_line "$OUT" 'order=carapace,kubectl,'; assert_line "$(cs_gen_log)" 'carapace _carapace zsh'
    assert_file "$CS_SB/$CS_CACHE/carapace-init.zsh"
    csession 'echo "order=$ORDER"' "$CS_SB"
    assert_line "$OUT" 'order=carapace,kubectl,'
    assert_eq "$(cs_gen_count)" 2 "carapace and kubectl each generated once"
}
scenario_completions_aws() {
    CS_TOOLS="aws aws_completer"
    csession 'echo "aws=${_comps[aws]}"'
    assert_line "$OUT" 'aws=_bash_complete -C aws_completer'; assert_empty "$ERR"
    CS_TOOLS="aws"
    csession 'echo "aws=[${_comps[aws]}]"'
    assert_line "$OUT" 'aws=[]'
}
scenario_completions_missing_silent() {
    CS_TOOLS=""
    csession 'echo "compdef=${+functions[compdef]}"'
    assert_empty "$ERR"; assert_eq "$CODE" 0; assert_line "$OUT" compdef=1
    assert_no_file "$CS_SB/$CS_CACHE/kubectl-completion.zsh"
    assert_no_file "$CS_SB/$CS_CACHE/carapace-init.zsh"
}
