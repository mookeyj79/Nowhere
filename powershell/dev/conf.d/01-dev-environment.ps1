# =============================================================================
#  01-dev-environment.ps1  (dev layer: devbox only)
#  Dev-machine defaults; local.ps1 values still win.
# =============================================================================

if (-not $NowhereEditor) { $env:EDITOR = 'code --wait' }
$env:VISUAL = $env:EDITOR
