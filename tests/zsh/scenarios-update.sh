#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for zsh/core/bin/update (list: scenarios-update.txt).

# Sandbox: bootstrap sandbox plus the update script and a fake uv, with
# bootstrap already run so every pin is in place.
new_update_sandbox() {
    new_bootstrap_sandbox
    mkdir -p "$BS_CLONE/zsh/core"
    cp -r "$REPO_ROOT/zsh/core/bin" "$BS_CLONE/zsh/core/bin"
    cp "$BS_BIN/uv.fake" "$BS_BIN/uv"
    run_bootstrap server
    [ "$BS_CODE" -eq 0 ] || fail "sandbox bootstrap failed: $BS_OUT"
    rm -f "$BS_BIN/apt.log" "$BS_BIN/uv.log" "$BS_BIN/curl.log"
}

run_update() { bs_run zsh/core/bin/update; }

plugin_dir() { echo "$BS_HOME/.local/share/nowhere/plugins/$1"; }

scenario_update_apt() {
    new_update_sandbox; run_update
    assert_eq "$BS_CODE" 0 "$BS_OUT"
    assert_line "$(bs_log apt.log)" "apt-get update"
    assert_line "$(bs_log apt.log)" "apt-get upgrade -y"
}
scenario_update_uv() {
    new_update_sandbox; run_update
    assert_line "$(bs_log uv.log)" "uv self update"
    rm "$BS_BIN/uv"; run_update
    assert_eq "$BS_CODE" 0 "absent uv is not an error: $BS_OUT"
}
scenario_update_plugins_drift() {
    new_update_sandbox
    local d sha
    d=$(plugin_dir zsh-autosuggestions)
    sha=$(git -C "$d" rev-parse HEAD)
    git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m drift
    run_update
    assert_eq "$BS_CODE" 0 "$BS_OUT"
    assert_eq "$(git -C "$d" rev-parse HEAD)" "$sha" "plugin returned to pin"
}
scenario_update_plugins_repin() {
    new_update_sandbox
    local n=zsh-autosuggestions src new
    src=$BS_ROOT/plugsrc/$n
    echo more >> "$src/$n.plugin.zsh"
    git -C "$src" -c user.name=t -c user.email=t@t commit -q -am next
    new=$(git -C "$src" rev-parse HEAD)
    jq --arg n "$n" --arg s "$new" '(.plugins[] | select(.name == $n) | .sha) = $s' \
        "$BS_CLONE/zsh/plugins.json" > "$BS_ROOT/p.json" && mv "$BS_ROOT/p.json" "$BS_CLONE/zsh/plugins.json"
    run_update
    assert_eq "$BS_CODE" 0 "$BS_OUT"
    assert_eq "$(git -C "$(plugin_dir $n)" rev-parse HEAD)" "$new" "plugin moved to new pin"
}
scenario_update_plugins_missing() {
    new_update_sandbox
    rm -rf "$(plugin_dir zsh-syntax-highlighting)"
    run_update
    assert_eq "$BS_CODE" 0 "$BS_OUT"
    assert_file "$(plugin_dir zsh-syntax-highlighting)/zsh-syntax-highlighting.plugin.zsh"
}
scenario_update_uvtool_repin() {
    new_update_sandbox
    # the manifest moved server-motd to a new commit: update follows it
    local src=git+https://github.com/mookeyj79/Server-MOTD@1111111111111111111111111111111111111111
    jq --arg s "$src" '(.uvTools[] | select(.name == "server-motd") | .source) = $s' \
        "$BS_CLONE/shared/tools.json" > "$BS_ROOT/t.json" && mv "$BS_ROOT/t.json" "$BS_CLONE/shared/tools.json"
    run_update
    assert_eq "$BS_CODE" 0 "$BS_OUT"
    assert_line "$(bs_log uv.log)" "uv tool install server-motd @ $src"
    run_update
    assert_eq "$(bs_log uv.log | grep -c 'tool install')" 1 'reinstalled when already at the pin'
}
scenario_update_release_missing() {
    new_update_sandbox
    rm -f "$BS_HOME/.local/bin/gitleaks"
    run_update
    assert_eq "$BS_CODE" 0 "$BS_OUT"
    [ -x "$BS_HOME/.local/bin/gitleaks" ] || fail 'gitleaks not reinstalled'
    assert_eq "$(bs_log curl.log | grep -c gitleaks)" 1 'gitleaks not downloaded once'
    assert_eq "$(bs_log curl.log | grep -c starship)" 0 'starship downloaded though at its pin'
}
scenario_update_continues() {
    new_update_sandbox
    printf '#!/bin/sh\nexit 1\n' > "$BS_BIN/apt-get"
    run_update
    [ "$BS_CODE" -ne 0 ] || fail "failed apt should fail update"
    assert_line "$(bs_log uv.log)" "uv self update"
}
scenario_update_idempotent() {
    new_update_sandbox; run_update
    local before after
    before=$(git -C "$(plugin_dir zsh-autosuggestions)" rev-parse HEAD)
    run_update
    after=$(git -C "$(plugin_dir zsh-autosuggestions)" rev-parse HEAD)
    assert_eq "$BS_CODE" 0 "$BS_OUT"; assert_eq "$after" "$before"
}
