# =============================================================================
#  profile.ps1  --  Nowhere PowerShell entry point
#
#  Reached through a few-line stub at $PROFILE that sets $env:NOWHERE_ROLE
#  (devbox | server) and dot-sources this file from the clone.
#
#  Order: local override first (~/.config/nowhere/local.ps1), then core/conf.d
#  merged with dev/conf.d (devbox only) in one filename order. Every value the
#  override can set is read with a default, so a missing override still works.
# =============================================================================

$global:NowhereProfileDir = $PSScriptRoot
$global:NowhereRepoDir    = Split-Path $PSScriptRoot -Parent
$global:NowhereRole       = if ($env:NOWHERE_ROLE -eq 'devbox') { 'devbox' } else { 'server' }

# --- Local override ---------------------------------------------------------
$_localOverride = Join-Path $HOME '.config/nowhere/local.ps1'
if (Test-Path -LiteralPath $_localOverride) { . $_localOverride }

if (-not $env:NOWHERE_HOME) { $env:NOWHERE_HOME = $global:NowhereRepoDir }

# --- Layers -----------------------------------------------------------------
$_layers = @('core')
if ($global:NowhereRole -eq 'devbox') { $_layers += 'dev' }

foreach ($_layer in $_layers) {
    $_bin = Join-Path $PSScriptRoot "$_layer/bin"
    if (Test-Path $_bin) { $env:PATH = $_bin + [IO.Path]::PathSeparator + $env:PATH }
}

$_files = foreach ($_layer in $_layers) {
    Get-ChildItem (Join-Path $PSScriptRoot "$_layer/conf.d") -Filter '*.ps1' -File -ErrorAction SilentlyContinue
}
foreach ($_file in ($_files | Sort-Object Name)) { . $_file.FullName }

Remove-Variable _localOverride, _layers, _layer, _bin, _files, _file -ErrorAction SilentlyContinue
