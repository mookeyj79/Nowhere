# =============================================================================
#  50-init.ps1
#  Zoxide (smart cd) and Starship (prompt). Must be last — Starship
#  overwrites $function:prompt and needs to see all env vars already set.
#
#  Both init scripts are cached by binary mtime (Get-NowhereCachedInit in
#  00-environment). On a warm cache each costs one stat() call at startup
#  instead of spawning a subprocess.
# =============================================================================

# --- zoxide (frecency-based smart cd) ---------------------------------------
#  --cmd cd takes over the built-in cd verb so muscle memory works unchanged.
#  Use `cdi` for the interactive picker when you want to fuzzy-select a dest.
$_init = Get-NowhereCachedInit zoxide-init zoxide @('init', 'powershell', '--cmd', 'cd')
if ($_init) { . $_init }

# --- Starship (must be last — overwrites the prompt function) ---------------
#  Config: the single shared shared/starship.toml in the clone.
if (Test-NowhereTool starship) {
    $_starshipConfig = Join-Path $global:NowhereRepoDir 'shared/starship.toml'
    if (Test-Path $_starshipConfig) { $env:STARSHIP_CONFIG = $_starshipConfig }
    $_init = Get-NowhereCachedInit starship-init starship @('init', 'powershell')
    if ($_init) { . $_init }
}

Remove-Variable _init, _starshipConfig -ErrorAction SilentlyContinue

# --- One bootstrap hint per session if any core tool is missing -------------
$_missing = $global:NowhereCoreTools | Where-Object { -not (Test-NowhereTool $_) }
if ($_missing -and -not $global:NowhereHintShown) {
    $global:NowhereHintShown = $true
    Write-Host "Nowhere: some tools are missing ($($_missing -join ', ')); run bootstrap to install them." -ForegroundColor DarkGray
}
Remove-Variable _missing
