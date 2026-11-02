#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for the Linux Server role (list: scenarios-server.txt).

# server-motd is not on PyPI: it is pinned by 'source', a git URL at a commit.
motd_source() { jq -r '.uvTools[] | select(.name == "server-motd") | .source' "$BS_CLONE/shared/tools.json"; }

scenario_server_motd_install() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_line "$(bs_log uv.log)" "uv tool install server-motd @ $(motd_source)"
    # system-wide, not under the installing user's home (the hook runs as root)
    assert_match "$(bs_log uv.env.log)" "tool install server-motd @ .* \\[dir=$BS_UVTOOL_DIR bin=$BS_UVTOOL_BIN\\]"
    assert_file "$BS_UVTOOL_BIN/server-motd"
    assert_no_file "$BS_HOME/.local/bin/server-motd"
    run_bootstrap server; assert_eq "$BS_CODE" 0 "second run failed: $BS_OUT"
    assert_eq "$(bs_log uv.log | grep -c 'tool install')" 1 'reinstalled on second run'
}
scenario_server_motd_repin() {
    new_bootstrap_sandbox
    # installed at an older commit, same version number: the pin moved, so reinstall
    mkdir -p "$BS_UVTOOL_DIR"
    echo 'server-motd v0.1.0 [required:  git+https://github.com/mookeyj79/Server-MOTD@0000000000000000000000000000000000000000]' > "$BS_UVTOOL_DIR/uvtools.txt"
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_line "$(bs_log uv.log)" "uv tool install server-motd @ $(motd_source)"
}
scenario_server_motd_source_pinned() {
    local src; src=$(jq -r '.uvTools[] | select(.name == "server-motd") | .source' "$REPO_ROOT/shared/tools.json")
    assert_match "$src" '^git\+https://.+@[0-9a-f]{40}$'
}
scenario_server_motd_config() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local cfg=$BS_MOTD_CONF/config.toml
    assert_file "$cfg"
    assert_eq "$(stat -c %a "$cfg")" 600 'config mode'
    cmp -s "$cfg" "$BS_CLONE/shared/server-motd/config.toml.example" || fail 'config differs from example'
    echo 'mine = 1' > "$cfg"
    run_bootstrap server; assert_eq "$BS_CODE" 0 "second run failed: $BS_OUT"
    assert_eq "$(cat "$cfg")" 'mine = 1' 'config overwritten'
}
scenario_server_motd_hook() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local hook=$BS_MOTD_DIR/50-server-motd
    assert_file "$hook"
    [ -x "$hook" ] || fail 'hook not executable'
    assert_match "$(head -1 "$hook")" '^#!/bin/sh'
    assert_line "$(cat "$hook")" "exec '$BS_UVTOOL_BIN/server-motd'"
    assert_line "$(cat "$hook")" "[ -x '$BS_UVTOOL_BIN/server-motd' ] || exit 0"
    assert_match "$(cat "$hook")" '^PATH='   # update-motd.d runs with a bare environment
    assert_eq "$("$hook")" 'server-motd motd' 'hook output'
    local before; before=$(cat "$hook")
    run_bootstrap server; assert_eq "$BS_CODE" 0 "second run failed: $BS_OUT"
    assert_eq "$(cat "$hook")" "$before" 'hook changed on rerun'
    # a missing binary makes the hook a silent no-op, never a login error
    rm -f "$BS_UVTOOL_BIN/server-motd"
    assert_empty "$("$hook" 2>&1)" 'hook output without binary'
    "$hook" > /dev/null 2>&1 || fail 'hook exits non-zero without the binary'
}
scenario_server_motd_hook_devbox() {
    new_bootstrap_sandbox
    run_bootstrap devbox; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    assert_no_file "$BS_MOTD_DIR/50-server-motd"
    assert_no_file "$BS_MOTD_CONF/config.toml"
    assert_eq "$(bs_log uv.log | grep -c 'tool install')" 0 'server-motd installed on devbox'
}
scenario_server_no_dev() {
    new_bootstrap_sandbox
    run_bootstrap server; assert_eq "$BS_CODE" 0 "bootstrap failed: $BS_OUT"
    local id installed; installed=$(bs_log installed.txt)
    for id in $(jq -r '.tools[] | select(.layer == "dev") | .packages.apt // empty' "$BS_CLONE/shared/tools.json"); do
        assert_no_line "$installed" "$id"
    done
}
scenario_server_profile_no_motd() {
    reset_session
    SESSION_TOOLS='server-motd'
    session server 'echo done'
    assert_line "$OUT" 'done'
    assert_no_line "$OUT" server-motd   # the shim echoes its own name if called
    ! grep -rq 'server-motd' "$REPO_ROOT/zsh" || fail 'zsh profile mentions server-motd'
}
