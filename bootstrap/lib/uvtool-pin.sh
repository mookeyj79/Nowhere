#!/usr/bin/env bash
# =============================================================================
#  uvtool-pin.sh  (source it)
#
#  Part of pins (pins.sh): how pins recognises a uv tool already at its pin.
#  Kept in its own file so tests/uvtools-smoke.sh can check it against the
#  listing the real uv prints; the sandbox suites only ever see fake uvs.
#
#    uv_pinned <spec> <listing>
#      does <listing>, the output of `uv tool list --show-version-specifiers`,
#      show this exact pin?
#        name @ source   a "name v..." line ending in " <source>]"
#        name==version   a "name v<version>" line
#
#  The Windows counterpart is UvToolPin.ps1, with the same rule.
# =============================================================================

uv_pinned() {
    local spec=$1 listed=$2 name version
    case "$spec" in
        *" @ "*)
            name=${spec%% @ *}
            grep -E "^$name v" <<< "$listed" | grep -qF " ${spec#* @ }]" ;;
        *)
            name=${spec%%==*}; version=${spec#*==}
            grep -qE "^$name v${version//./\\.}( |\$)" <<< "$listed" ;;
    esac
}
