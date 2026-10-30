#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for the ZSH dev layer, zsh/dev/conf.d (ids in scenarios-dev.txt).
# Dev tools are shims that echo their name and argv, so an alias or function can
# be run and its expansion observed.

ALL_DEV_SHIMS="kubectl helm docker terraform tofu"
DEV_ALIASES="k kgp kgs kgd kgn kga kd kl kex kctx h dc dcup dcdn dcl dcr dcps dcb dcpl dce dps tf tfi tfp tfa tfd tff to toi topl toa"

scenario_dev_aliases_all() {
    local probe='for a in '"$DEV_ALIASES"'; do echo "$a=${+aliases[$a]}"; done'
    reset_session; SESSION_TOOLS="$ALL_DEV_SHIMS"
    session devbox "$probe"
    assert_empty "$ERR"
    local a
    for a in $DEV_ALIASES; do assert_line "$OUT" "$a=1"; done
    session server "$probe"
    assert_empty "$ERR"
    for a in $DEV_ALIASES; do assert_line "$OUT" "$a=0"; done
}
scenario_dev_aliases_run() {
    reset_session; SESSION_TOOLS="$ALL_DEV_SHIMS"
    session devbox 'eval "topl -x"; eval kgp; eval tfp; eval dcup; eval dps; eval "h ls"'
    assert_empty "$ERR"
    assert_line "$OUT" 'tofu plan -x'
    assert_line "$OUT" 'kubectl get pods'
    assert_line "$OUT" 'terraform plan'
    assert_line "$OUT" 'docker compose up -d'
    assert_line "$OUT" 'docker ps'
    assert_line "$OUT" 'helm ls'
}
scenario_dev_tool_gating() {
    local probe='echo "k=${+aliases[k]} h=${+aliases[h]} dc=${+aliases[dc]} tf=${+aliases[tf]} to=${+aliases[to]} kns=${+functions[kns]}"'
    reset_session; SESSION_TOOLS="tofu"
    session devbox "$probe"
    assert_empty "$ERR"; assert_line "$OUT" 'k=0 h=0 dc=0 tf=0 to=1 kns=0'
    reset_session; SESSION_TOOLS="kubectl helm"
    session devbox "$probe"
    assert_empty "$ERR"; assert_line "$OUT" 'k=1 h=1 dc=0 tf=0 to=0 kns=1'
}
scenario_dev_kns() {
    reset_session; SESSION_TOOLS="kubectl"
    session devbox 'kns prod; kns d; kns default'
    assert_empty "$ERR"
    assert_line "$OUT" 'kubectl config set-context --current --namespace=prod'
    assert_eq "$(count_matching "$OUT" 'namespace=default')" 2 'd and default both map to default'
    session server 'echo "kns=${+functions[kns]}"'
    assert_line "$OUT" kns=0
}
scenario_dev_editor() {
    reset_session; SESSION_TOOLS=""
    session devbox 'echo "editor=$EDITOR"; echo "visual=$VISUAL"'
    assert_line "$OUT" 'editor=code --wait'; assert_line "$OUT" 'visual=code --wait'
    SESSION_LOCAL='NowhereEditor=vim'
    session devbox 'echo "editor=$EDITOR"; echo "visual=$VISUAL"'
    assert_line "$OUT" editor=vim; assert_line "$OUT" visual=vim
    reset_session
    session server 'echo "editor=$EDITOR"'
    assert_line "$OUT" editor=nano
}
scenario_dev_boot_tools() {
    local pkgs="kubernetes-client docker-cli gh"
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local installed p; installed=$(bs_log installed.txt)
    for p in $pkgs; do assert_line "$installed" "$p"; done
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    installed=$(bs_log installed.txt)
    for p in $pkgs; do assert_no_line "$installed" "$p"; done
}