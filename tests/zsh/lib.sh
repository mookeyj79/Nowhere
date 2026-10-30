#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC2010
# Sandbox seams for the zsh harness (sourced by run.sh, never run directly).
#
#   session   run a real zsh against a throwaway HOME through a stub that sets
#             NOWHERE_ROLE and sources zsh/profile.zsh from this clone
#   bootstrap run bootstrap/bootstrap.sh in a throwaway HOME and clone, with a
#             fake apt/dpkg/sudo/curl on PATH (no network, no sudo, no real
#             machine state touched)

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ZSH_BIN=$(command -v zsh || true)
SANDBOXES=()

cleanup_sandboxes() {
    local d
    for d in "${SANDBOXES[@]}"; do rm -rf "$d"; done
    SANDBOXES=()
}

new_dir() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/nowhere-zsh.XXXXXX")
    SANDBOXES+=("$d")
    echo "$d"
}

# --- assertions (a failing one ends the scenario subshell) ---------------------
fail() { echo "    FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$2], got [$1]"; }
# Assertions feed grep through a here-string, never a pipe: run.sh uses pipefail,
# and `printf | grep -q` makes printf die of SIGPIPE when grep exits at the first
# match, which failed a scenario at random (core-venv-activate).
assert_line() { grep -qxF -- "$2" <<< "$1" || fail "output lacks line [$2]; output was: $1"; }
assert_no_line() { ! grep -qxF -- "$2" <<< "$1" || fail "output unexpectedly has line [$2]"; }
assert_empty() { [ -z "$1" ] || fail "${2:-expected empty}: [$1]"; }
assert_file() { [ -e "$1" ] || fail "missing $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected $1"; }
assert_match() { grep -qE -- "$2" <<< "$1" || fail "[$1] does not match /$2/"; }
count_matching() { printf '%s\n' "$1" | grep -c -- "$2" || true; }

# --- zsh session sandbox --------------------------------------------------------
# Inputs (globals, reset by reset_session): SESSION_LOCAL (override text, unset =
# no file), SESSION_TOOLS (shim names; unset = a PATH with no tools at all),
# SESSION_PLUGINS (stub plugins), SESSION_FZF_ZSH (what the fzf shim prints for --zsh).
# Outputs: OUT (stdout), ERR (stderr), CODE.
reset_session() { unset SESSION_LOCAL SESSION_TOOLS SESSION_PLUGINS SESSION_FZF_ZSH SESSION_REAL; }

session() {
    local role=$1 probe=${2:-:}
    local sb home bin
    sb=$(new_dir); home=$sb/home; bin=$sb/bin
    mkdir -p "$home/.config/nowhere" "$bin" "$sb/xdg"
    if [ "${SESSION_LOCAL+set}" = set ]; then printf '%s\n' "$SESSION_LOCAL" > "$home/.config/nowhere/local.zsh"; fi
    local t
    for t in ${SESSION_TOOLS:-}; do
        printf '#!/bin/sh\necho %s "$@"\n' "$t" > "$bin/$t"
        chmod +x "$bin/$t"
    done
    if [ "${SESSION_FZF_ZSH+set}" = set ] && [ -x "$bin/fzf" ]; then
        printf '#!/bin/sh\n[ "$1" = --zsh ] && while IFS= read -r l; do printf "%%s\\n" "$l"; done < "%s/fzf-zsh.txt"\n' "$sb" > "$bin/fzf"
        printf '%s\n' "$SESSION_FZF_ZSH" > "$sb/fzf-zsh.txt"
    fi
    for t in ${SESSION_REAL:-}; do   # real binaries (mkdir, cat...) linked into the bin
        ln -s "$(command -v "$t")" "$bin/$t"
    done
    if [ "${SESSION_PLUGINS+set}" = set ]; then
        local spec name file body
        for spec in $SESSION_PLUGINS; do   # name:relative/file:VAR (file sets VAR=1)
            name=${spec%%:*}; file=${spec#*:}; body=${file#*:}; file=${file%%:*}
            mkdir -p "$home/.local/share/nowhere/plugins/$name/$(dirname "$file")"
            printf '%s=1\nORDER="${ORDER}%s,"\n' "$body" "$name" > "$home/.local/share/nowhere/plugins/$name/$file"
        done
    fi
    {
        [ -n "$role" ] && echo "export NOWHERE_ROLE='$role'"
        echo "source '$REPO_ROOT/zsh/profile.zsh'"
    } > "$home/stub.zsh"
    CODE=0
    OUT=$(env -i HOME="$home" PATH="$bin" XDG_CACHE_HOME="$sb/xdg" ORDER= \
        "$ZSH_BIN" -f -c "source '$home/stub.zsh'; $probe" 2> "$sb/err") || CODE=$?
    ERR=$(cat "$sb/err")
}

# --- bootstrap sandbox ------------------------------------------------------------
# Sets BS_ROOT BS_BIN BS_CLONE BS_HOME and a ready fake environment.
new_bootstrap_sandbox() {
    BS_ROOT=$(new_dir); BS_BIN=$BS_ROOT/fakebin; BS_CLONE=$BS_ROOT/clone; BS_HOME=$BS_ROOT/home
    mkdir -p "$BS_BIN" "$BS_HOME" "$BS_CLONE"
    BS_FAKE_SHAS=()

    # Fake apt-get / dpkg: installed.txt is the "installed packages" database.
    cat > "$BS_BIN/dpkg" << 'EOF'
#!/bin/sh
[ "$1" = "-s" ] && [ -f "$FAKE_BIN/installed.txt" ] && grep -qxF "$2" "$FAKE_BIN/installed.txt"
EOF
    cat > "$BS_BIN/apt-get" << 'EOF'
#!/bin/sh
echo "apt-get $*" >> "$FAKE_BIN/apt.log"
[ "$1" = "install" ] && for a in "$@"; do case "$a" in -*|install) ;; *) echo "$a" >> "$FAKE_BIN/installed.txt" ;; esac; done
exit 0
EOF
    printf '#!/bin/sh\nexec "$@"\n' > "$BS_BIN/sudo"
    # Fake curl: a fake archive per release tool (matched by tool name in the URL),
    # a tiny script for the uv installer.
    cat > "$BS_BIN/curl" << 'EOF'
#!/bin/sh
out=""; prev=""; url=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out=$a
    prev=$a; url=$a
done
echo "$url" >> "$FAKE_BIN/curl.log"
case "$url" in
    *astral.sh*) printf 'cp "%s/uv.fake" "%s/uv"\n' "$FAKE_BIN" "$FAKE_BIN" > "$out" ;;
    *)
        for f in "$FAKE_BIN"/rel/*; do
            n=${f##*/}
            case "$url" in *"$n"*) cp "$f" "$out"; exit 0 ;; esac
        done
        exit 22 ;;
esac
EOF
    # Fake uv (what the "installer" drops): logs calls and keeps a tool list and bin dir
    # under UV_TOOL_DIR / UV_TOOL_BIN_DIR, like the real uv (bootstrap sets both).
    cat > "$BS_BIN/uv.fake" << 'EOF'
#!/bin/sh
echo "uv $*" >> "$FAKE_BIN/uv.log"
[ -z "$UV_TOOL_DIR" ] || echo "uv $* [dir=$UV_TOOL_DIR bin=$UV_TOOL_BIN_DIR]" >> "$FAKE_BIN/uv.env.log"
case "$1 $2" in
    "tool list") cat "$UV_TOOL_DIR/uvtools.txt" 2> /dev/null ;;
    "tool install")
        n=${3%%==*}; v=${3#*==}
        mkdir -p "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR"
        echo "$n v$v" >> "$UV_TOOL_DIR/uvtools.txt"
        printf '#!/bin/sh\necho %s motd\n' "$n" > "$UV_TOOL_BIN_DIR/$n"; chmod +x "$UV_TOOL_BIN_DIR/$n" ;;
esac
EOF
    BS_MOTD_DIR=$BS_ROOT/update-motd.d; BS_MOTD_CONF=$BS_ROOT/etc-server-motd
    BS_UVTOOL_DIR=$BS_ROOT/opt-uv-tools; BS_UVTOOL_BIN=$BS_ROOT/usr-local-bin
    chmod +x "$BS_BIN/dpkg" "$BS_BIN/apt-get" "$BS_BIN/sudo" "$BS_BIN/curl" "$BS_BIN/uv.fake"

    # A fake release archive per manifest 'release' tool, in the manifest's own
    # archive format, holding the member path (for both arch spellings) that
    # prints "<name> <pinned version>" for any arguments.
    local rname rver rarch rmember rfmt m
    mkdir -p "$BS_BIN/rel"
    while IFS=$'\t' read -r rname rver rfmt rmember; do
        mkdir -p "$BS_ROOT/arsrc/$rname"
        for rarch in $(jq -r --arg n "$rname" '.tools[] | select(.name == $n) | (.release.arch // {x64: "x64", arm64: "arm64"}) | .[]' "$REPO_ROOT/shared/tools.json"); do
            m=${rmember//\{version\}/$rver}; m=${m//\{arch\}/$rarch}
            mkdir -p "$BS_ROOT/arsrc/$rname/$(dirname "$m")"
            printf '#!/bin/sh\necho %s %s\n' "$rname" "$rver" > "$BS_ROOT/arsrc/$rname/$m"
            chmod +x "$BS_ROOT/arsrc/$rname/$m"
        done
        if [ "$rfmt" = zip ]; then
            (cd "$BS_ROOT/arsrc/$rname" && python3 -c 'import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1], "w")
for d, _, fs in os.walk("."):
    for f in fs:
        z.write(os.path.join(d, f), os.path.relpath(os.path.join(d, f), "."))' "$BS_BIN/rel/$rname")
        else
            # members without a leading ./, like the real archives
            (cd "$BS_ROOT/arsrc/$rname" && find . -type f -printf '%P\n' | tar -czf "$BS_BIN/rel/$rname" -T -)
        fi
        BS_FAKE_SHAS+=("$rname=$(sha256sum "$BS_BIN/rel/$rname" | cut -d' ' -f1)")
    done < <(jq -r '.tools[] | select(.release) | [.name, .release.version, (.release.archive // "tar.gz"), (.release.member // .name)] | @tsv' "$REPO_ROOT/shared/tools.json")

    # A minimal clone: the real bootstrap, manifests and example, in a fresh git repo.
    local p
    for p in bootstrap shared/tools.json shared/server-motd zsh/plugins.json zsh/local.zsh.example .githooks; do
        mkdir -p "$BS_CLONE/$(dirname "$p")"
        cp -r "$REPO_ROOT/$p" "$BS_CLONE/$p"
    done
    # Pin each fake archive's checksum for every arch, so any host passes.
    local kv
    for kv in "${BS_FAKE_SHAS[@]}"; do
        jq --arg n "${kv%%=*}" --arg s "${kv#*=}" '(.tools[] | select(.name == $n) | .release.sha256[]) |= $s' \
            "$BS_CLONE/shared/tools.json" > "$BS_ROOT/t.json" && mv "$BS_ROOT/t.json" "$BS_CLONE/shared/tools.json"
    done
    # Plugins: local one-commit repos instead of GitHub, same names, pinned by real SHA.
    local names n repo sha
    names=$(jq -r '.plugins[].name' "$REPO_ROOT/zsh/plugins.json")
    echo '{"plugins":[]}' > "$BS_CLONE/zsh/plugins.json"
    for n in $names; do
        repo=$BS_ROOT/plugsrc/$n
        mkdir -p "$repo"
        git -C "$repo" init -q
        echo "# $n" > "$repo/$n.plugin.zsh"
        git -C "$repo" add -A
        git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m init
        sha=$(git -C "$repo" rev-parse HEAD)
        jq --arg n "$n" --arg r "$repo" --arg s "$sha" '.plugins += [{name: $n, repo: $r, sha: $s}]' \
            "$BS_CLONE/zsh/plugins.json" > "$BS_ROOT/p.json" && mv "$BS_ROOT/p.json" "$BS_CLONE/zsh/plugins.json"
    done
    git -C "$BS_CLONE" init -q
}

# Run bootstrap in the sandbox. Sets BS_OUT and BS_CODE.
run_bootstrap() {
    BS_CODE=0
    BS_OUT=$(env -i HOME="$BS_HOME" PATH="$BS_BIN:/usr/bin:/bin" FAKE_BIN="$BS_BIN" GIT_CONFIG_NOSYSTEM=1 \
        NOWHERE_MOTD_DIR="$BS_MOTD_DIR" NOWHERE_MOTD_CONFIG_DIR="$BS_MOTD_CONF" \
        NOWHERE_UVTOOL_DIR="$BS_UVTOOL_DIR" NOWHERE_UVTOOL_BIN_DIR="$BS_UVTOOL_BIN" \
        bash "$BS_CLONE/bootstrap/bootstrap.sh" "$@" 2>&1) || BS_CODE=$?
}

bs_log() { cat "$BS_BIN/$1" 2> /dev/null || true; }
