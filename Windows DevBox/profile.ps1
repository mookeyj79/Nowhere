# =============================================================================
#  Microsoft.PowerShell_profile.ps1
#  Place at: $PROFILE  (run `$PROFILE` in pwsh to find the exact path)
#
#  Sources conf.d\*.ps1, then profile.d\*.ps1, each in name order. Drop or
#  add files there to enable/disable features without touching this file.
# =============================================================================

$_profileDir = Split-Path $PROFILE -Parent
foreach ($_dir in 'conf.d', 'profile.d') {
    Get-ChildItem (Join-Path $_profileDir $_dir) -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }
}
Remove-Variable _profileDir, _dir
