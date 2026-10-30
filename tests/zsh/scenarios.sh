#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2010
# Scenario implementations. Each scenario_<id> runs in its own subshell; the id
# list and the pwsh counterparts live in tests/scenarios.txt. A failed assert_*
# ends the scenario.

# --- profile: role gating ------------------------------------------------------
scenario_role_devbox() {
    reset_session; SESSION_TOOLS="git tofu"
    session devbox 'echo "core=${+aliases[gst]}"; echo "dev=${+aliases[topl]}"; echo "editor=$EDITOR"'
    assert_empty "$ERR"; assert_line "$OUT" core=1; assert_line "$OUT" dev=1; assert_line "$OUT" 'editor=code --wait'
}
scenario_role_server() {
    reset_session; SESSION_TOOLS="git tofu"
    session server 'echo "core=${+aliases[gst]}"; echo "dev=${+aliases[topl]}"; echo "editor=$EDITOR"'
    assert_empty "$ERR"; assert_line "$OUT" core=1; assert_line "$OUT" dev=0; assert_line "$OUT" editor=nano
}
scenario_role_unset() {
    reset_session; SESSION_TOOLS="git tofu"
    session '' 'echo "dev=${+aliases[topl]}"'
    assert_line "$OUT" dev=0
}

# --- profile: local override -----------------------------------------------------
scenario_local_none() {
    reset_session; SESSION_TOOLS="git"
    session devbox 'echo "confcrypt=[$CONFCRYPT_HOME]"; echo "home=$NOWHERE_HOME"'
    assert_empty "$ERR"; assert_eq "$CODE" 0
    assert_line "$OUT" 'confcrypt=[]'; assert_line "$OUT" "home=$REPO_ROOT"
}
scenario_local_wins() {
    reset_session; SESSION_TOOLS="git"
    SESSION_LOCAL='NowhereEditor=vim; export CONFCRYPT_HOME=/x/confcrypt'
    session devbox 'echo "editor=$EDITOR"; echo "confcrypt=$CONFCRYPT_HOME"'
    assert_empty "$ERR"; assert_line "$OUT" editor=vim; assert_line "$OUT" confcrypt=/x/confcrypt
}
scenario_local_nowhere_home() {
    reset_session; SESSION_TOOLS="git"
    SESSION_LOCAL='export NOWHERE_HOME=/custom/clone'
    session server 'echo "home=$NOWHERE_HOME"'
    assert_line "$OUT" home=/custom/clone
}
scenario_local_empty() {
    reset_session; SESSION_TOOLS="git"; SESSION_LOCAL=''
    session server 'echo "editor=$EDITOR"'
    assert_empty "$ERR"; assert_line "$OUT" editor=nano
}

# --- profile: contract -----------------------------------------------------------
scenario_tool_guard_git() {
    reset_session; SESSION_TOOLS="git"
    session server 'echo "gst=${+aliases[gst]}"'
    assert_line "$OUT" gst=1
    reset_session; SESSION_TOOLS=""
    session server 'echo "gst=${+aliases[gst]}"'
    assert_line "$OUT" gst=0; assert_empty "$ERR"
}
scenario_dev_aliases_guarded() {
    local probe='echo "tfp=${+aliases[tfp]}"; echo "kgp=${+aliases[kgp]}"; echo "dcup=${+aliases[dcup]}"; echo "topl=${+aliases[topl]}"'
    reset_session; SESSION_TOOLS=""
    session devbox "$probe"
    assert_empty "$ERR"; assert_line "$OUT" tfp=0; assert_line "$OUT" kgp=0; assert_line "$OUT" dcup=0
    reset_session; SESSION_TOOLS="terraform kubectl docker tofu"
    session devbox "$probe"
    assert_line "$OUT" tfp=1; assert_line "$OUT" kgp=1; assert_line "$OUT" dcup=1; assert_line "$OUT" topl=1
    session server "$probe"
    assert_line "$OUT" tfp=0; assert_line "$OUT" topl=0
}
scenario_missing_tools_hint() {
    reset_session; SESSION_TOOLS=""
    session devbox 'echo ok'
    assert_empty "$ERR"; assert_line "$OUT" ok
    assert_eq "$(count_matching "$OUT" bootstrap)" 1 'hint count'
}
scenario_no_hint_when_complete() {
    reset_session; SESSION_TOOLS="starship zoxide carapace fzf eza git"
    SESSION_PLUGINS="catppuccin-zsh-syntax-highlighting:themes/catppuccin_macchiato-zsh-syntax-highlighting.zsh:A zsh-syntax-highlighting:zsh-syntax-highlighting.zsh:B"
    session server 'echo ok'
    assert_eq "$(count_matching "$OUT" bootstrap)" 0 'hint count'
}

# --- profile: plugin directory convention ----------------------------------------
scenario_plugin_skip() {
    reset_session; SESSION_TOOLS="starship zoxide carapace fzf eza git"
    session devbox 'echo "ok"'
    assert_empty "$ERR"; assert_line "$OUT" ok
    assert_eq "$(count_matching "$OUT" bootstrap)" 1 'one hint for missing plugins'
}
scenario_plugin_load() {
    reset_session; SESSION_TOOLS="starship zoxide carapace fzf eza git"
    SESSION_PLUGINS="catppuccin-zsh-syntax-highlighting:themes/catppuccin_macchiato-zsh-syntax-highlighting.zsh:THEME_LOADED zsh-syntax-highlighting:zsh-syntax-highlighting.zsh:SYNTAX_LOADED"
    session server 'echo "theme=$THEME_LOADED syntax=$SYNTAX_LOADED order=$ORDER"'
    assert_empty "$ERR"
    assert_line "$OUT" 'theme=1 syntax=1 order=catppuccin-zsh-syntax-highlighting,zsh-syntax-highlighting,'
    assert_eq "$(count_matching "$OUT" 'run bootstrap')" 0 'no hint when plugins present'
}

# --- bootstrap --------------------------------------------------------------------
scenario_boot_reject_role() {
    new_bootstrap_sandbox
    run_bootstrap laptop
    [ "$BS_CODE" -ne 0 ] || fail 'invalid role accepted'
    assert_no_file "$BS_HOME/.zshrc"
    assert_empty "$(bs_log apt.log)"
}
scenario_boot_manifest_sane() {
    local m=$REPO_ROOT/shared/tools.json dup
    dup=$(jq -r '.tools[].name' "$m" | sort | uniq -d)
    assert_empty "$dup" 'duplicate tool names'
    assert_eq "$(jq '[.tools[] | select(.layer != "core" and .layer != "dev")] | length' "$m")" 0 'bad layer'
    assert_eq "$(jq -r '.tools[] | select(.name == "btop") | .packages.winget' "$m")" aristocratos.btop4win
    # gitleaks: pinned version and a sha256 for each Linux arch
    assert_match "$(jq -r '.tools[] | select(.name == "gitleaks") | .release.version' "$m")" '^[0-9]+\.[0-9]+\.[0-9]+$'
    assert_match "$(jq -r '.tools[] | select(.name == "gitleaks") | .release.sha256.x64' "$m")" '^[0-9a-f]{64}$'
    assert_match "$(jq -r '.tools[] | select(.name == "gitleaks") | .release.sha256.arm64' "$m")" '^[0-9a-f]{64}$'
    # plugins: exact 40-hex SHAs
    assert_eq "$(jq '[.plugins[] | select(.sha | test("^[0-9a-f]{40}$") | not)] | length' "$REPO_ROOT/zsh/plugins.json")" 0 'unpinned plugin'
    assert_eq "$(jq '.plugins | length' "$REPO_ROOT/zsh/plugins.json")" 4 'plugin count'
}
scenario_boot_tools_devbox() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local installed id
    installed=$(bs_log installed.txt)
    for id in $(jq -r '.tools[] | .packages.apt // empty' "$BS_CLONE/shared/tools.json"); do
        assert_line "$installed" "$id"
    done
    assert_line "$installed" gh
}
scenario_boot_tools_server() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local installed
    installed=$(bs_log installed.txt)
    assert_line "$installed" zoxide
    assert_no_line "$installed" gh
}
scenario_boot_uv() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_eq "$(bs_log curl.log | grep -c astral.sh)" 1 'uv installer runs once'
    assert_file "$BS_BIN/uv"
}
scenario_boot_uv_present() {
    new_bootstrap_sandbox
    printf '#!/bin/sh\n' > "$BS_BIN/uv"; chmod +x "$BS_BIN/uv"
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_eq "$(bs_log curl.log | grep -c astral.sh)" 0 'uv installer skipped'
}
scenario_boot_stub() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local stub; stub=$(cat "$BS_HOME/.zshrc")
    assert_match "$stub" "NOWHERE_ROLE='server'"
    assert_match "$stub" "source '$BS_CLONE/zsh/profile.zsh'"
}
scenario_boot_stub_backup() {
    new_bootstrap_sandbox
    echo 'my precious zshrc' > "$BS_HOME/.zshrc"
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local baks; baks=$(ls -A "$BS_HOME" | grep -c '^\.zshrc\.bak-' || true)
    assert_eq "$baks" 1 'backup count'
    assert_match "$(cat "$BS_HOME"/.zshrc.bak-*)" 'my precious zshrc'
    assert_match "$(cat "$BS_HOME/.zshrc")" NOWHERE_ROLE
}
scenario_boot_local_seed() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local f=$BS_HOME/.config/nowhere/local.zsh
    cmp -s "$f" "$BS_CLONE/zsh/local.zsh.example" || fail 'override differs from example'
    assert_eq "$(stat -c %a "$f")" 600 'override mode'
}
scenario_boot_local_keep() {
    new_bootstrap_sandbox
    mkdir -p "$BS_HOME/.config/nowhere"
    local f=$BS_HOME/.config/nowhere/local.zsh
    echo 'export MY_TOKEN=keep' > "$f"; chmod 644 "$f"
    local before; before=$(cksum < "$f")
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_eq "$(cksum < "$f")" "$before" 'override changed'
    assert_eq "$(stat -c %a "$f")" 644 'override mode touched'
}
scenario_boot_hooks() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_eq "$(git -C "$BS_CLONE" config core.hooksPath)" .githooks
}
scenario_boot_idempotent() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "first run failed: $BS_OUT"
    local apt1 curl1 stub1 over1
    apt1=$(bs_log apt.log); curl1=$(bs_log curl.log)
    stub1=$(stat -c %Y "$BS_HOME/.zshrc"); over1=$(stat -c %Y "$BS_HOME/.config/nowhere/local.zsh")
    sleep 1
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "second run failed: $BS_OUT"
    assert_eq "$(bs_log apt.log)" "$apt1" 'apt called again'
    assert_eq "$(bs_log curl.log)" "$curl1" 'curl called again'
    assert_eq "$(stat -c %Y "$BS_HOME/.zshrc")" "$stub1" 'stub rewritten'
    assert_eq "$(stat -c %Y "$BS_HOME/.config/nowhere/local.zsh")" "$over1" 'override rewritten'
    assert_eq "$(ls -A "$BS_HOME" | grep -c bak- || true)" 0 'backups made'
}
scenario_boot_gitleaks_release() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local ver; ver=$(jq -r '.tools[] | select(.name == "gitleaks") | .release.version' "$BS_CLONE/shared/tools.json")
    [ -x "$BS_HOME/.local/bin/gitleaks" ] || fail 'gitleaks not installed'
    assert_eq "$("$BS_HOME/.local/bin/gitleaks" version)" "$ver"
    assert_match "$(bs_log curl.log)" "download/v$ver/gitleaks_${ver}_linux_"
    assert_no_line "$(bs_log installed.txt)" gitleaks
    run_bootstrap server
    assert_eq "$(bs_log curl.log | grep -c gitleaks)" 1 'gitleaks downloaded twice'
}
scenario_boot_gitleaks_badsum() {
    new_bootstrap_sandbox
    local zeros; zeros=$(printf '0%.0s' $(seq 64))
    jq --arg z "$zeros" '(.tools[] | select(.release) | .release.sha256[]) |= $z' \
        "$BS_CLONE/shared/tools.json" > "$BS_ROOT/t.json" && mv "$BS_ROOT/t.json" "$BS_CLONE/shared/tools.json"
    run_bootstrap server
    [ "$BS_CODE" -ne 0 ] || fail 'bad checksum accepted'
    assert_match "$BS_OUT" 'checksum'
    assert_no_file "$BS_HOME/.local/bin/gitleaks"
}
scenario_boot_plugins_pinned() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local name sha dir
    while IFS=$'\t' read -r name sha; do
        dir=$BS_HOME/.local/share/nowhere/plugins/$name
        assert_eq "$(git -C "$dir" rev-parse HEAD)" "$sha" "$name not at pinned SHA"
    done < <(jq -r '.plugins[] | [.name, .sha] | @tsv' "$BS_CLONE/zsh/plugins.json")
    # a plugin drifted off its pin is moved back, not left alone
    local first; first=$(jq -r '.plugins[0].name' "$BS_CLONE/zsh/plugins.json")
    dir=$BS_HOME/.local/share/nowhere/plugins/$first
    git -C "$dir" -c user.name=t -c user.email=t@t commit -q --allow-empty -m drift
    run_bootstrap server; assert_eq "$BS_CODE" 0 "rerun failed: $BS_OUT"
    assert_eq "$(git -C "$dir" rev-parse HEAD)" "$(jq -r '.plugins[0].sha' "$BS_CLONE/zsh/plugins.json")" 'drift not corrected'
}
