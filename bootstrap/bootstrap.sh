#!/usr/bin/env bash
# =============================================================================
#  bootstrap.sh <devbox|server>
#
#  Readies a Debian/Ubuntu machine for Nowhere. Safe to re-run: every step
#  checks state first and does nothing when already done.
#
#    0. prerequisites (jq, curl, ca-certificates) via apt
#    1. tools from shared/tools.json via apt (core always, dev on devbox)
#    2. pinned release binaries (gitleaks) into ~/.local/bin, sha256-checked
#    3. uv via Astral's official installer, only when not on PATH
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
apt_ensure jq curl ca-certificates

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

install_release() {
    local name=$1 version url want have got
    version=$(jq -r --arg n "$name" '.tools[] | select(.name == $n) | .release.version' "$MANIFEST")
    have=$("$BIN_DIR/$name" version 2> /dev/null || true)
    [ "${have#v}" = "$version" ] && return 0
    [ -n "$ARCH" ] || die "no $name release binary for $(uname -m)"
    url=$(jq -r --arg n "$name" '.tools[] | select(.name == $n) | .release.url' "$MANIFEST")
    url=${url//\{version\}/$version}
    url=${url//\{arch\}/$ARCH}
    want=$(jq -r --arg n "$name" --arg a "$ARCH" '.tools[] | select(.name == $n) | .release.sha256[$a] // empty' "$MANIFEST")
    [ -n "$want" ] || die "no pinned checksum for $name $ARCH"
    step "installing $name $version (release binary)"
    mkdir -p "$TMP/$name"
    curl -fsSL -o "$TMP/$name.tar.gz" "$url" || die "download failed: $url"
    got=$(sha256sum "$TMP/$name.tar.gz" | cut -d' ' -f1)
    [ "$got" = "$want" ] || die "checksum mismatch for $name (expected $want, got $got)"
    tar -xzf "$TMP/$name.tar.gz" -C "$TMP/$name" "$name"
    mkdir -p "$BIN_DIR"
    install -m 755 "$TMP/$name/$name" "$BIN_DIR/$name"
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
