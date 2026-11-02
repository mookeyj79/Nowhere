#!/usr/bin/env bash
# =============================================================================
#  bootstrap.sh <devbox|server>
#
#  Readies a Debian/Ubuntu machine for Nowhere. Safe to re-run: every step
#  checks state first and does nothing when already done.
#
#    0. prerequisites (jq, curl, ca-certificates, unzip) via apt
#    1. tools from shared/tools.json via apt (core always, dev on devbox)
#    2. pinned release binaries (manifest 'release' blocks: starship, carapace,
#       gitleaks, and on a devbox helm, terraform, tofu) into ~/.local/bin,
#       sha256-checked
#    3. uv via Astral's official installer, only when not on PATH
#    3b. server only: server-motd via a system-wide `uv tool install` (root-owned
#       /opt + /usr/local/bin) at the manifest pin, config seeded (no overwrite,
#       600), root-owned update-motd.d hook
#    4. zsh plugins cloned at pinned SHAs into ~/.local/share/nowhere/plugins
#    5. ~/.zshrc stub (a different existing stub is backed up)
#    6. local override seeded from local.zsh.example if missing, mode 600
#    7. git core.hooksPath = .githooks in this clone
#
#  Everything is rooted at $HOME and the clone this script lives in, so the
#  sandbox tests only need a throwaway HOME and a fake package manager on PATH.
# =============================================================================
set -euo pipefail

usage() { echo "usage: bootstrap.sh <devbox|server>" >&2; exit 2; }
[ $# -eq 1 ] || usage
ROLE=$1
case "$ROLE" in devbox | server) ;; *) usage ;; esac

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
case "$REPO_ROOT" in *"'"*) echo "clone path must not contain a single quote" >&2; exit 1 ;; esac
MANIFEST=$REPO_ROOT/shared/tools.json
BIN_DIR=$HOME/.local/bin
PLUGIN_DIR=$HOME/.local/share/nowhere/plugins
CONFIG_DIR=$HOME/.config/nowhere
ZSHRC=$HOME/.zshrc

step() { echo "==> $*"; }
die() { echo "bootstrap: $*" >&2; exit 1; }

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO=sudo
export PATH="$BIN_DIR:$PATH"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

APT_UPDATED=""
apt_ensure() {
    local pkg
    for pkg in "$@"; do
        dpkg -s "$pkg" > /dev/null 2>&1 && continue
        if [ -z "$APT_UPDATED" ]; then
            step "apt-get update"
            $SUDO apt-get update
            APT_UPDATED=1
        fi
        step "installing $pkg"
        $SUDO apt-get install -y "$pkg" || die "apt-get failed to install $pkg"
    done
}

# --- 0. Prerequisites --------------------------------------------------------
apt_ensure jq curl ca-certificates unzip

# --- 1. Tools ----------------------------------------------------------------
DEV=false
[ "$ROLE" = devbox ] && DEV=true
# shellcheck disable=SC2016  # $dev is a jq variable
LAYER_FILTER='select(.layer == "core" or ($dev and .layer == "dev"))'
mapfile -t APT_IDS < <(jq -r --argjson dev "$DEV" ".tools[] | $LAYER_FILTER | .packages.apt // empty" "$MANIFEST")
apt_ensure "${APT_IDS[@]}"

# --- 2. Pinned release binaries ----------------------------------------------
case "$(uname -m)" in
    x86_64 | amd64) ARCH=x64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) ARCH="" ;;
esac

# One installer for every manifest 'release' block (see the $comment in
# shared/tools.json). Download, verify against the pinned sha256, extract the
# one binary, install it. Skipped when the installed binary already reports
# the pinned version.
install_release() {
    local name=$1 rel version url want have got archive member vargs aname
    rel=$(jq -c --arg n "$name" '.tools[] | select(.name == $n) | .release' "$MANIFEST")
    version=$(jq -r '.version' <<< "$rel")
    vargs=$(jq -r '.versionArgs // "version"' <<< "$rel")
    # shellcheck disable=SC2086  # versionArgs is a space-separated argument list
    have=$("$BIN_DIR/$name" $vargs 2>&1 || true)
    if printf '%s\n' "$have" | grep -qE "(^|[^0-9.])${version//./\.}([^0-9.]|\$)"; then return 0; fi
    [ -n "$ARCH" ] || die "no $name release binary for $(uname -m)"
    aname=$(jq -r --arg a "$ARCH" '.arch[$a] // $a' <<< "$rel")
    url=$(jq -r '.url' <<< "$rel")
    url=${url//\{version\}/$version}
    url=${url//\{arch\}/$aname}
    want=$(jq -r --arg a "$ARCH" '.sha256[$a] // empty' <<< "$rel")
    [ -n "$want" ] || die "no pinned checksum for $name $ARCH"
    archive=$(jq -r '.archive // "tar.gz"' <<< "$rel")
    member=$(jq -r --arg n "$name" '.member // $n' <<< "$rel")
    member=${member//\{version\}/$version}
    member=${member//\{arch\}/$aname}
    step "installing $name $version (release binary)"
    mkdir -p "$TMP/$name"
    curl -fsSL -o "$TMP/$name.$archive" "$url" || die "download failed: $url"
    got=$(sha256sum "$TMP/$name.$archive" | cut -d' ' -f1)
    [ "$got" = "$want" ] || die "checksum mismatch for $name (expected $want, got $got)"
    case "$archive" in
        tar.gz) tar -xzf "$TMP/$name.$archive" -C "$TMP/$name" "$member" || die "cannot extract $member from $name archive" ;;
        zip) unzip -oq "$TMP/$name.$archive" "$member" -d "$TMP/$name" || die "cannot extract $member from $name archive" ;;
        *) die "unknown archive type $archive for $name" ;;
    esac
    mkdir -p "$BIN_DIR"
    install -m 755 "$TMP/$name/$member" "$BIN_DIR/$name"
}
mapfile -t RELEASE_TOOLS < <(jq -r --argjson dev "$DEV" ".tools[] | $LAYER_FILTER | select(.release) | .name" "$MANIFEST")
for tool in "${RELEASE_TOOLS[@]}"; do install_release "$tool"; done

# --- 3. uv (official installer, only when absent) -----------------------------
WANT_UV=$(jq -r --argjson dev "$DEV" "[.tools[] | $LAYER_FILTER | select(.installer == \"astral\")] | length" "$MANIFEST")
if [ "$WANT_UV" -gt 0 ] && ! command -v uv > /dev/null 2>&1; then
    step "installing uv (official installer)"
    curl -fsSL -o "$TMP/uv-install.sh" https://astral.sh/uv/install.sh || die "uv installer download failed"
    sh "$TMP/uv-install.sh"
fi

# --- 3b. uv tools (server-motd on servers) -------------------------------------
# The MOTD banner is printed by a root-owned /etc/update-motd.d hook at login,
# never by the zsh profile (that would print it twice). The hook runs as root,
# so the tool is installed machine-wide (UV_TOOL_DIR under /opt, binary in
# /usr/local/bin, both root-owned via sudo) rather than under the installing
# user's home, where root would be executing a user-writable file.
MOTD_DIR=${NOWHERE_MOTD_DIR:-/etc/update-motd.d}
MOTD_CONFIG_DIR=${NOWHERE_MOTD_CONFIG_DIR:-/etc/server-motd}
UVTOOL_DIR=${NOWHERE_UVTOOL_DIR:-/opt/nowhere/uv-tools}
UVTOOL_BIN_DIR=${NOWHERE_UVTOOL_BIN_DIR:-/usr/local/bin}
uv_system_tool() {
    # sudo's secure_path hides ~/.local/bin, so hand it uv by absolute path.
    $SUDO env "UV_TOOL_DIR=$UVTOOL_DIR" "UV_TOOL_BIN_DIR=$UVTOOL_BIN_DIR" "$(command -v uv)" tool "$@"
}
# A tool is pinned by 'version' (PyPI: name==version) or 'source' (a git URL at
# a commit: name @ source); '-' marks the absent one, since a tab IFS merges
# empty fields. Installed means `uv tool list --show-version-specifiers` shows
# that exact pin; anything else is (re)installed.
while IFS=$'\t' read -r name version source; do
    command -v uv > /dev/null 2>&1 || die "uv not found; cannot install $name"
    listed=$(uv_system_tool list --show-version-specifiers 2> /dev/null | grep -E "^$name v" || true)
    if [ "$source" != - ]; then
        spec="$name @ $source"
        case "$listed" in *" $source]"*) spec= ;; esac
    else
        spec="$name==$version"
        case "$listed" in "$name v$version "* | "$name v$version") spec= ;; esac
    fi
    if [ -n "$spec" ]; then
        step "installing $spec (uv tool, system-wide)"
        uv_system_tool install "$spec" || die "uv tool install $name failed"
    fi
    if [ "$name" = server-motd ]; then
        MOTD_BIN=$UVTOOL_BIN_DIR/$name
        $SUDO test -x "$MOTD_BIN" || die "$name not found at $MOTD_BIN after install"
        if ! $SUDO test -e "$MOTD_CONFIG_DIR/config.toml"; then
            $SUDO install -D -m 600 "$REPO_ROOT/shared/server-motd/config.toml.example" "$MOTD_CONFIG_DIR/config.toml"
            step "seeded $MOTD_CONFIG_DIR/config.toml (owner-only)"
        fi
        # update-motd.d runs with a bare environment (no ~/.local/bin on PATH, no
        # HOME), so the hook calls the binary by absolute path. It exits quietly if
        # the binary is gone, so a broken install can never break a login.
        printf '#!/bin/sh\nPATH=/usr/local/bin:/usr/bin:/bin\n[ -x '"'%s'"' ] || exit 0\nexec '"'%s'"'\n' "$MOTD_BIN" "$MOTD_BIN" > "$TMP/50-server-motd"
        if ! $SUDO cmp -s "$TMP/50-server-motd" "$MOTD_DIR/50-server-motd"; then
            $SUDO install -D -m 755 "$TMP/50-server-motd" "$MOTD_DIR/50-server-motd"
            step "wrote $MOTD_DIR/50-server-motd"
        fi
    fi
done < <(jq -r --arg r "$ROLE" '.uvTools[]? | select(.roles | index($r)) | [.name, (.version // "-"), (.source // "-")] | @tsv' "$MANIFEST")

# --- 4. Pinned zsh plugins ----------------------------------------------------
while IFS=$'\t' read -r name repo sha; do
    dir=$PLUGIN_DIR/$name
    if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2> /dev/null)" = "$sha" ]; then
        continue
    fi
    step "installing plugin $name @ ${sha:0:12}"
    mkdir -p "$PLUGIN_DIR"
    [ -d "$dir/.git" ] || git clone --quiet "$repo" "$dir"
    git -C "$dir" cat-file -e "$sha^{commit}" 2> /dev/null || git -C "$dir" fetch --quiet origin
    git -C "$dir" -c advice.detachedHead=false checkout --quiet "$sha"
done < <(jq -r '.plugins[] | [.name, .repo, .sha] | @tsv' "$REPO_ROOT/zsh/plugins.json")

# --- 5. Stub -----------------------------------------------------------------
STUB="# Nowhere stub (written by bootstrap.sh). Logic lives in the clone.
export NOWHERE_ROLE='$ROLE'
source '$REPO_ROOT/zsh/profile.zsh'"
CURRENT=""
[ -e "$ZSHRC" ] && CURRENT=$(cat "$ZSHRC")
if [ ! -e "$ZSHRC" ] || [ "$CURRENT" != "$STUB" ]; then
    if [ -e "$ZSHRC" ]; then
        BAK="$ZSHRC.bak-$(date +%Y%m%d%H%M%S)"
        mv "$ZSHRC" "$BAK"
        step "existing .zshrc backed up to $BAK"
    fi
    printf '%s\n' "$STUB" > "$ZSHRC"
    step "wrote stub $ZSHRC"
fi

# --- 6. Local override -------------------------------------------------------
OVERRIDE=$CONFIG_DIR/local.zsh
if [ ! -e "$OVERRIDE" ]; then
    mkdir -p "$CONFIG_DIR"
    (umask 077 && cp "$REPO_ROOT/zsh/local.zsh.example" "$OVERRIDE")
    chmod 600 "$OVERRIDE"
    step "seeded $OVERRIDE (owner-only)"
fi

# --- 7. Secrets hook ---------------------------------------------------------
git -C "$REPO_ROOT" config core.hooksPath .githooks || die "git config core.hooksPath failed"

step "bootstrap complete ($ROLE)"
