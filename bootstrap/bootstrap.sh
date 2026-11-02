#!/usr/bin/env bash
# =============================================================================
#  bootstrap.sh <devbox|server>
#
#  Readies a Debian/Ubuntu machine for Nowhere. Safe to re-run: every step
#  checks state first and does nothing when already done.
#
#    0. prerequisites (jq, curl, ca-certificates, unzip) via apt
#    1. apt packages from the install plan (lib/plan.sh: shared/tools.json,
#       core always, dev on devbox)
#    2. uv via Astral's official installer, only when not on PATH
#    3. pins (lib/pins.sh --strict): pinned release binaries (starship,
#       carapace, gitleaks, and on a devbox helm, terraform, tofu) into
#       ~/.local/bin, sha256-checked; on a server, server-motd as a
#       system-wide uv tool; zsh plugins at their pinned SHAs
#    4. server only: server-motd config seeded (no overwrite, 600) and the
#       root-owned update-motd.d hook
#    5. ~/.zshrc stub (a different existing stub is backed up)
#    6. local override seeded from local.zsh.example if missing, mode 600
#    7. git core.hooksPath = .githooks in this clone
#
#  Everything is rooted at $HOME and the clone this script lives in, so the
#  sandbox tests only need a throwaway HOME and a fake package manager on PATH.
#  NOWHERE_MOTD_DIR, NOWHERE_MOTD_CONFIG_DIR and NOWHERE_UVTOOL_BIN_DIR move
#  the root-owned paths for those tests.
# =============================================================================
set -euo pipefail

usage() { echo "usage: bootstrap.sh <devbox|server>" >&2; exit 2; }
[ $# -eq 1 ] || usage
ROLE=$1
case "$ROLE" in devbox | server) ;; *) usage ;; esac

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
case "$REPO_ROOT" in *"'"*) echo "clone path must not contain a single quote" >&2; exit 1 ;; esac
LIB=$REPO_ROOT/bootstrap/lib
BIN_DIR=$HOME/.local/bin
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

# --- 0. Prerequisites (the plan needs jq) ---------------------------------------
apt_ensure jq curl ca-certificates unzip

PLAN=$(bash "$LIB/plan.sh" "$ROLE") || die "cannot read the install plan"
# planned <kind>: the first field after the kind, one line per planned action
planned() { awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<< "$PLAN"; }

# --- 1. apt packages ------------------------------------------------------------
mapfile -t APT_IDS < <(planned apt)
apt_ensure "${APT_IDS[@]}"

# --- 2. uv (official installer, only when absent) -------------------------------
if grep -qx uv <<< "$(planned installer)" && ! command -v uv > /dev/null 2>&1; then
    step "installing uv (official installer)"
    curl -fsSL -o "$TMP/uv-install.sh" https://astral.sh/uv/install.sh || die "uv installer download failed"
    sh "$TMP/uv-install.sh"
fi

# --- 3. Pins: release binaries, uv tools, zsh plugins ---------------------------
bash "$LIB/pins.sh" "$ROLE" --strict || die "could not bring every pin into place"

# --- 4. server-motd config and login hook ---------------------------------------
# The banner is printed by a root-owned /etc/update-motd.d hook at login, never
# by the zsh profile (that would print it twice).
if grep -qx server-motd <<< "$(planned uvtool)"; then
    MOTD_DIR=${NOWHERE_MOTD_DIR:-/etc/update-motd.d}
    MOTD_CONFIG_DIR=${NOWHERE_MOTD_CONFIG_DIR:-/etc/server-motd}
    MOTD_BIN=${NOWHERE_UVTOOL_BIN_DIR:-/usr/local/bin}/server-motd
    $SUDO test -x "$MOTD_BIN" || die "server-motd not found at $MOTD_BIN after install"
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
