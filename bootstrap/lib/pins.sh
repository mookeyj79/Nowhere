#!/usr/bin/env bash
# =============================================================================
#  pins.sh <devbox|server> [--strict]
#
#  Brings a Linux machine to the pins in its plan (plan.sh):
#    release   binaries at their pinned version and sha256, into ~/.local/bin
#    uvtool    uv tools at their pinned spec, machine-wide
#    plugin    zsh plugins at their pinned SHA, in ~/.local/share/nowhere/plugins
#  Anything already at its pin is left alone, so it is safe to run any number
#  of times. bootstrap.sh runs it with --strict (stop at the first failure);
#  update runs it without (report each failure, carry on, exit 1 at the end).
#
#  uv tools are installed machine-wide and root-owned via sudo: server-motd
#  runs from a root update-motd.d hook, which must never execute a file the
#  user can write. NOWHERE_UVTOOL_DIR and NOWHERE_UVTOOL_BIN_DIR move them
#  (the sandbox tests use these).
# =============================================================================
set -uo pipefail

usage() { echo "usage: pins.sh <devbox|server> [--strict]" >&2; exit 2; }
[ $# -ge 1 ] || usage
ROLE=$1; shift
case "$ROLE" in devbox | server) ;; *) usage ;; esac
STRICT=false
case "${1:-}" in --strict) STRICT=true ;; "") ;; *) usage ;; esac

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=bootstrap/lib/uvtool-pin.sh
. "$HERE/uvtool-pin.sh"
BIN_DIR=$HOME/.local/bin
PLUGIN_DIR=$HOME/.local/share/nowhere/plugins
UVTOOL_DIR=${NOWHERE_UVTOOL_DIR:-/opt/nowhere/uv-tools}
UVTOOL_BIN_DIR=${NOWHERE_UVTOOL_BIN_DIR:-/usr/local/bin}
FAILED=0

step() { echo "==> $*"; }
# Strict: stop here. Otherwise: report, remember, and let the caller move on.
fail() {
    echo "pins: $*" >&2
    $STRICT && exit 1
    FAILED=1
}

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO=sudo
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- release binaries -----------------------------------------------------------
# Skipped when the installed binary already reports the pinned version.
pin_release() {
    local name=$1 version=$2 url=$3 want=$4 archive=$5 member=$6 vargs=$7 have got
    # shellcheck disable=SC2086  # versionArgs is a space-separated argument list
    have=$("$BIN_DIR/$name" $vargs 2>&1 || true)
    if printf '%s\n' "$have" | grep -qE "(^|[^0-9.])${version//./\.}([^0-9.]|\$)"; then return 0; fi
    [ "$url" != - ] || { fail "no pinned $name release binary for $(uname -m)"; return; }
    step "installing $name $version (release binary)"
    mkdir -p "$TMP/$name"
    curl -fsSL -o "$TMP/$name.$archive" "$url" || { fail "download failed: $url"; return; }
    got=$(sha256sum "$TMP/$name.$archive" | cut -d' ' -f1)
    [ "$got" = "$want" ] || { fail "checksum mismatch for $name (expected $want, got $got)"; return; }
    case "$archive" in
        tar.gz) tar -xzf "$TMP/$name.$archive" -C "$TMP/$name" "$member" || { fail "cannot extract $member from $name archive"; return; } ;;
        zip) unzip -oq "$TMP/$name.$archive" "$member" -d "$TMP/$name" || { fail "cannot extract $member from $name archive"; return; } ;;
        *) fail "unknown archive type $archive for $name"; return ;;
    esac
    mkdir -p "$BIN_DIR"
    install -m 755 "$TMP/$name/$member" "$BIN_DIR/$name" || fail "cannot install $name into $BIN_DIR"
}

# --- uv tools -------------------------------------------------------------------
uv_system_tool() {
    # sudo's secure_path hides ~/.local/bin, so hand it uv by absolute path.
    $SUDO env "UV_TOOL_DIR=$UVTOOL_DIR" "UV_TOOL_BIN_DIR=$UVTOOL_BIN_DIR" "$(command -v uv)" tool "$@"
}
# uv_pinned <spec> <listing>: uvtool-pin.sh, also checked against the real uv
# by tests/uvtools-smoke.sh.
pin_uvtool() {
    local name=$1 spec=$2 listed
    if ! command -v uv > /dev/null 2>&1; then
        if $STRICT; then fail "uv not found; cannot install $name"; else echo "uv not found, skipping $name (run bootstrap)"; fi
        return
    fi
    listed=$(uv_system_tool list --show-version-specifiers 2> /dev/null || true)
    uv_pinned "$spec" "$listed" && return 0
    step "installing $spec (uv tool, system-wide)"
    uv_system_tool install "$spec" || fail "uv tool install $name failed"
}

# --- zsh plugins ----------------------------------------------------------------
pin_plugin() {
    local name=$1 repo=$2 sha=$3 dir=$PLUGIN_DIR/$1
    if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2> /dev/null)" = "$sha" ]; then return 0; fi
    step "plugin $name @ ${sha:0:12}"
    mkdir -p "$PLUGIN_DIR"
    if [ ! -d "$dir/.git" ]; then
        git clone --quiet "$repo" "$dir" || { fail "clone failed: $name"; return; }
    fi
    git -C "$dir" cat-file -e "$sha^{commit}" 2> /dev/null || git -C "$dir" fetch --quiet origin
    git -C "$dir" -c advice.detachedHead=false checkout --quiet "$sha" || fail "checkout failed: $name"
}

# --- main -----------------------------------------------------------------------
command -v jq > /dev/null 2>&1 || { fail "jq not found (run bootstrap)"; exit 1; }
PLAN=$(bash "$HERE/plan.sh" "$ROLE") || { fail "cannot read the install plan"; exit 1; }
HAVE_GIT=true
command -v git > /dev/null 2>&1 || HAVE_GIT=false

while IFS=$'\t' read -r kind a b c d e f g; do
    case "$kind" in
        release) pin_release "$a" "$b" "$c" "$d" "$e" "$f" "$g" ;;
        uvtool) pin_uvtool "$a" "$b" ;;
        plugin)
            if $HAVE_GIT; then pin_plugin "$a" "$b" "$c"; else fail "git not found, skipping plugin $a"; fi ;;
    esac
done <<< "$PLAN"

exit "$FAILED"
