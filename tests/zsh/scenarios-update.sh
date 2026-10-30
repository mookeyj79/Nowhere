#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for zsh/core/bin/update (list: scenarios-update.txt).

# Sandbox: bootstrap sandbox plus the update script and a fake uv, with
# bootstrap already run so plugins sit at their pins.
new_update_sandbox() {
    new_bootstrap_sandbox
    mkdir -p "$BS_CLONE/zsh/core"
    cp -r "$REPO_ROOT/zsh/core/bin" "$BS_CLONE/zsh/core/bin"
    printf '#!/bin/sh\necho "uv $*" >> "$FAKE_BIN/uv.log"\n' > "$BS_BIN/uv"
    chmod +x "$BS_BIN/uv"
    run_bootstrap server
    [ "$BS_CODE" -eq 0 ] || fail "sandbox bootstrap failed: $BS_OUT"
    rm -f "$BS_BIN/apt.log"
}

# Sets UP_OUT and UP_CODE.
run_update() {
    UP_CODE=0
    UP_OUT=$(env -i HOME="$BS_HOME" PATH="$BS_BIN:/usr/bin:/bin" FAKE_BIN="$BS_BIN" GIT_CONFIG_NOSYSTEM=1 \
        bash "$BS_CLONE/zsh/core/bin/update" 2>&1) || UP_CODE=$?
}

plugin_dir() { echo "$BS_HOME/.local/share/nowhere/plugins/$1"; }

scenario_update_apt() {
    new_update_sandbox; run_update
    assert_eq "$UP_CODE" 0 "$UP_OUT"
    assert_line "$(bs_log apt.log)" "apt-get update"
    assert_line "$(bs_log apt.log)" "apt-get upgrade -y"
}
scenario_update_uv() {
    new_update_sandbox; run_update
    assert_line "$(bs_log uv.log)" "uv self update"
    rm "$BS_BIN/uv"; run_update
    assert_eq "$UP_CODE" 0 "absent uv is not an error"
}
scenario_update_plugins_drift() {
    new_update_sandbox
    local d sha
    d=$(plugin_dir zsh-autosuggestions)
    sha=$(git -C "$d" rev-parse HEAD)
    git -C "$d" -c user.name=t -c user.email=t@t commit -q --allow-empty -m drift
    run_update
    assert_eq "$UP_CODE" 0 "$UP_OUT"
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
    assert_eq "$UP_CODE" 0 "$UP_OUT"
    assert_eq "$(git -C "$(plugin_dir $n)" rev-parse HEAD)" "$new" "plugin moved to new pin"
}
scenario_update_plugins_missing() {
    new_update_sandbox
    rm -rf "$(plugin_dir zsh-syntax-highlighting)"
    run_update
    assert_eq "$UP_CODE" 0 "$UP_OUT"
    assert_file "$(plugin_dir zsh-syntax-highlighting)/zsh-syntax-highlighting.plugin.zsh"
}
scenario_update_continues() {
    new_update_sandbox
    printf '#!/bin/sh\nexit 1\n' > "$BS_BIN/apt-get"
    run_update
    [ "$UP_CODE" -ne 0 ] || fail "failed apt should fail update"
    assert_line "$(bs_log uv.log)" "uv self update"
}
scenario_update_idempotent() {
    new_update_sandbox; run_update
    local before after
    before=$(git -C "$(plugin_dir zsh-autosuggestions)" rev-parse HEAD)
    run_update
    after=$(git -C "$(plugin_dir zsh-autosuggestions)" rev-parse HEAD)
    assert_eq "$UP_CODE" 0 "$UP_OUT"; assert_eq "$after" "$before"
}
