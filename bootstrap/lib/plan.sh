#!/usr/bin/env bash
# =============================================================================
#  plan.sh <devbox|server> [--arch x64|arm64|-] [--tools FILE] [--plugins FILE]
#
#  The Linux install plan: what shared/tools.json and zsh/plugins.json ask for
#  on this role, one action per line, tab-separated. Reads files only and
#  installs nothing. bootstrap.sh, pins.sh, the uvTools smoke test and the zsh
#  harness fakes read this instead of interpreting the manifests themselves.
#
#    apt       <package>
#    installer <tool> <installer>                 (uv: astral)
#    release   <tool> <version> <url> <sha256> <archive> <member> <versionArgs>
#    uvtool    <tool> <spec>                      (name==version or name @ source)
#    plugin    <name> <repo> <sha>
#
#  Release fields are resolved for --arch (default: this machine). An arch the
#  manifest has no binary or checksum for gives '-' for url and sha256. No
#  field is ever empty, so a tab IFS reads every line field for field.
# =============================================================================
set -euo pipefail

usage() { echo "usage: plan.sh <devbox|server> [--arch x64|arm64|-] [--tools FILE] [--plugins FILE]" >&2; exit 2; }
[ $# -ge 1 ] || usage
ROLE=$1; shift
case "$ROLE" in devbox | server) ;; *) usage ;; esac

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOLS=$REPO_ROOT/shared/tools.json
PLUGINS=$REPO_ROOT/zsh/plugins.json
case "$(uname -m)" in
    x86_64 | amd64) ARCH=x64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) ARCH=- ;;
esac
while [ $# -gt 0 ]; do
    case "$1" in
        --arch) ARCH=${2:?}; shift 2 ;;
        --tools) TOOLS=${2:?}; shift 2 ;;
        --plugins) PLUGINS=${2:?}; shift 2 ;;
        *) usage ;;
    esac
done

DEV=false
[ "$ROLE" = devbox ] && DEV=true

# shellcheck disable=SC2016  # $dev, $arch, $role are jq variables
jq -r --argjson dev "$DEV" --arg arch "$ARCH" --arg role "$ROLE" '
    def fill($v; $a): gsub("\\{version\\}"; $v) | gsub("\\{arch\\}"; $a);
    (.tools[] | select(.layer == "core" or ($dev and .layer == "dev")) |
        (.packages.apt // empty | ["apt", .]),
        (select(.installer) | ["installer", .name, .installer]),
        (select(.release) | .name as $n | .release as $r | ($r.arch[$arch] // $arch) as $a |
            ($r.sha256[$arch] // "-") as $sum |
            ["release", $n, $r.version,
             (if $sum == "-" then "-" else ($r.url | fill($r.version; $a)) end),
             $sum,
             ($r.archive // "tar.gz"),
             (($r.member // $n) | fill($r.version; $a)),
             ($r.versionArgs // "version")])),
    (.uvTools[]? | select(.roles | index($role)) |
        ["uvtool", .name, (if .source then "\(.name) @ \(.source)" else "\(.name)==\(.version)" end)])
    | @tsv' "$TOOLS"

if [ -f "$PLUGINS" ]; then
    jq -r '.plugins[] | ["plugin", .name, .repo, .sha] | @tsv' "$PLUGINS"
fi
