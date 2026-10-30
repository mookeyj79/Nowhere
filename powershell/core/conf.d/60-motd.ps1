# =============================================================================
#  60-motd.ps1
#  Windows Server login banner. Runs server-motd (installed by bootstrap via
#  `uv tool install`) only on the server role and only when it is on PATH; a
#  missing command does nothing. DevBoxes never show it.
#
#  server-motd's own install-profile / uninstall-profile are NOT used on
#  Nowhere machines: this file is the single hook, so the stub keeps one owner.
# =============================================================================

if ($global:NowhereRole -eq 'server' -and (Test-NowhereTool server-motd)) {
    server-motd
}
