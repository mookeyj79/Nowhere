#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2010
# Scenario implementations. Each scenario_<id> runs in its own subshell; the id
# list and the pwsh counterparts live in tests/scenarios.txt. A failed assert_*
# ends the scenario.

# Role gating, the local override, tool guards and the missing-tools hint are
# rows of tests/parity.txt (scenario_parity), shared with Pester.

# --- profile: local override -----------------------------------------------------
scenario_local_nowhere_home() {
    reset_session; SESSION_TOOLS="git"
    SESSION_LOCAL='export NOWHERE_HOME=/custom/clone'
    session server 'echo "home=$NOWHERE_HOME"'
    assert_line "$OUT" home=/custom/clone
    reset_session; SESSION_TOOLS="git"
    session server 'echo "home=$NOWHERE_HOME"'
    assert_line "$OUT" "home=$REPO_ROOT"
}

# --- profile: plugin directory convention ----------------------------------------
scenario_plugin_skip() {
    reset_session; SESSION_TOOLS="$CORE_TOOLS"
    session devbox 'echo "ok"'
    assert_empty "$ERR"; assert_line "$OUT" ok
    assert_eq "$(count_matching "$OUT" bootstrap)" 1 'one hint for missing plugins'
}
scenario_plugin_load() {
    reset_session; SESSION_TOOLS="$CORE_TOOLS"
    SESSION_PLUGINS="zsh-autosuggestions:zsh-autosuggestions.zsh:AS_LOADED zsh-history-substring-search:zsh-history-substring-search.zsh:HS_LOADED catppuccin-zsh-syntax-highlighting:themes/catppuccin_macchiato-zsh-syntax-highlighting.zsh:THEME_LOADED zsh-syntax-highlighting:zsh-syntax-highlighting.zsh:SYNTAX_LOADED"
    session server 'echo "theme=$THEME_LOADED syntax=$SYNTAX_LOADED order=$ORDER"'
    assert_empty "$ERR"
    assert_line "$OUT" 'theme=1 syntax=1 order=zsh-autosuggestions,zsh-history-substring-search,catppuccin-zsh-syntax-highlighting,zsh-syntax-highlighting,'
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
    assert_eq "$("$BS_HOME/.local/bin/gitleaks" version)" "gitleaks $ver"
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
scenario_boot_release_core() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local t ver
    for t in starship carapace gitleaks; do
        ver=$(jq -r --arg n "$t" '.tools[] | select(.name == $n) | .release.version' "$BS_CLONE/shared/tools.json")
        [ -x "$BS_HOME/.local/bin/$t" ] || fail "$t not installed"
        assert_match "$("$BS_HOME/.local/bin/$t" --version)" "$t $ver"
    done
    assert_no_file "$BS_HOME/.local/bin/helm"
    run_bootstrap server; assert_eq "$BS_CODE" 0 "rerun failed: $BS_OUT"
    for t in starship carapace gitleaks; do
        assert_eq "$(bs_log curl.log | grep -c "$t")" 1 "$t downloaded twice"
    done
}
scenario_boot_release_dev() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local t
    for t in helm terraform tofu; do
        [ -x "$BS_HOME/.local/bin/$t" ] || fail "$t not installed"
        assert_match "$("$BS_HOME/.local/bin/$t" version)" "^$t "
    done
    assert_match "$(bs_log curl.log)" 'terraform_.*_linux_.*\.zip'
}
scenario_boot_linux_routes() {
    local m=$REPO_ROOT/shared/tools.json miss
    # Every core tool needs an apt id, a pinned release or an installer on Linux.
    miss=$(jq -r '.tools[] | select(.layer == "core") | select((.packages.apt // .release // .installer) | not) | .name' "$m")
    assert_empty "$miss" 'core tools with no Linux route'
    # every release pins a version and a sha256 for both arches
    miss=$(jq -r '.tools[] | select(.release) | select((.release.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not) or (.release.sha256.x64 | test("^[0-9a-f]{64}$") | not) or (.release.sha256.arm64 | test("^[0-9a-f]{64}$") | not)) | .name' "$m")
    assert_empty "$miss" 'release pins incomplete'
    # code is the one documented devbox-manual gap
    assert_match "$(jq -r '."$comment"' "$m")" 'code.*devbox-manual'
    assert_match "$(cat "$REPO_ROOT/README.md")" 'devbox-manual'
}
