#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034
# Scenarios for bootstrap/lib/plan.sh (list: scenarios-plan.txt). The plan reads
# manifests and prints lines, so these run against fixture manifests: no
# sandbox, no fakes.

plan() { bash "$REPO_ROOT/bootstrap/lib/plan.sh" "$@"; }

# A fixture tools.json covering every manifest shape the plan interprets.
plan_fixture() {
    local d; d=$(new_dir)
    cat > "$d/tools.json" << 'EOF'
{ "tools": [
    { "name": "aptcore", "layer": "core", "packages": { "apt": "apt-core", "winget": "W.Core" } },
    { "name": "aptdev",  "layer": "dev",  "packages": { "apt": "apt-dev" } },
    { "name": "uv",      "layer": "core", "installer": "astral", "packages": {} },
    { "name": "plain",   "layer": "core", "packages": {},
      "release": { "version": "1.2.3", "url": "https://x/plain-{version}-{arch}.tar.gz",
                   "sha256": { "x64": "aaa", "arm64": "bbb" } } },
    { "name": "fancy",   "layer": "dev",  "packages": {},
      "release": { "version": "4.5.6", "url": "https://x/fancy_{version}_{arch}.zip",
                   "arch": { "x64": "amd64", "arm64": "arm64" }, "archive": "zip",
                   "member": "fancy-{arch}/fancy", "versionArgs": "version --short",
                   "sha256": { "x64": "ccc" } } }
  ],
  "uvTools": [
    { "name": "bysource",  "source": "git+https://x/y@0123", "roles": ["server"] },
    { "name": "byversion", "version": "0.9.1", "roles": ["server", "devbox"] }
  ] }
EOF
    echo '{"plugins":[{"name":"p1","repo":"https://x/p1","sha":"abc123"}]}' > "$d/plugins.json"
    echo "$d"
}

scenario_plan_layers() {
    local d out; d=$(plan_fixture)
    out=$(plan server --arch x64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_line "$out" "$(printf 'apt\tapt-core')"
    assert_no_line "$out" "$(printf 'apt\tapt-dev')"
    assert_line "$out" "$(printf 'installer\tuv\tastral')"
    assert_eq "$(count_matching "$out" '^release	fancy')" 0 'dev release on a server'
    out=$(plan devbox --arch x64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_line "$out" "$(printf 'apt\tapt-dev')"
    assert_eq "$(count_matching "$out" '^release	fancy')" 1 'dev release missing on a devbox'
}
scenario_plan_release() {
    local d out; d=$(plan_fixture)
    out=$(plan devbox --arch x64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    # defaults: tar.gz, member = tool name, versionArgs = version; {arch} as given
    assert_line "$out" "$(printf 'release\tplain\t1.2.3\thttps://x/plain-1.2.3-x64.tar.gz\taaa\ttar.gz\tplain\tversion')"
    # arch map, zip, templated member, versionArgs with a space
    assert_line "$out" "$(printf 'release\tfancy\t4.5.6\thttps://x/fancy_4.5.6_amd64.zip\tccc\tzip\tfancy-amd64/fancy\tversion --short')"
    # an arch with no checksum, or an unknown arch, gives '-' for url and sha256
    out=$(plan devbox --arch arm64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_line "$out" "$(printf 'release\tfancy\t4.5.6\t-\t-\tzip\tfancy-arm64/fancy\tversion --short')"
    out=$(plan devbox --arch - --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_line "$out" "$(printf 'release\tplain\t1.2.3\t-\t-\ttar.gz\tplain\tversion')"
}
scenario_plan_uvtools() {
    local d out; d=$(plan_fixture)
    out=$(plan server --arch x64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_line "$out" "$(printf 'uvtool\tbysource\tbysource @ git+https://x/y@0123')"
    assert_line "$out" "$(printf 'uvtool\tbyversion\tbyversion==0.9.1')"
    out=$(plan devbox --arch x64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_no_line "$out" "$(printf 'uvtool\tbysource\tbysource @ git+https://x/y@0123')"
    assert_line "$out" "$(printf 'uvtool\tbyversion\tbyversion==0.9.1')"
}
scenario_plan_plugins() {
    local d out; d=$(plan_fixture)
    out=$(plan server --arch x64 --tools "$d/tools.json" --plugins "$d/plugins.json")
    assert_line "$out" "$(printf 'plugin\tp1\thttps://x/p1\tabc123')"
}
scenario_plan_real_manifest() {
    # the shipped manifests plan cleanly on both roles, and no field is empty
    local role out
    for role in devbox server; do
        out=$(plan "$role") || fail "plan $role failed"
        [ -n "$out" ] || fail "empty plan for $role"
        assert_eq "$(count_matching "$out" "$(printf '\t\t')")" 0 "empty field in the $role plan"
    done
    assert_line "$(plan server)" "$(jq -r '.uvTools[] | select(.name == "server-motd") | "uvtool\t\(.name)\t\(.name) @ \(.source)"' "$REPO_ROOT/shared/tools.json")"
}
