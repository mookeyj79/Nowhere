# =============================================================================
#  50-init.ps1
#  Zoxide (smart cd) and Starship (prompt). Must be last — Starship
#  overwrites $function:prompt and needs to see all env vars already set.
#
#  Both init scripts are cached to disk by binary mtime. On a warm cache
#  each costs one stat() call at startup instead of spawning a subprocess.
# =============================================================================

$_cacheDir = $global:NowhereCacheDir
$null      = [System.IO.Directory]::CreateDirectory($_cacheDir)

# --- zoxide (frecency-based smart cd) ---------------------------------------
#  --cmd cd takes over the built-in cd verb so muscle memory works unchanged.
#  Use `cdi` for the interactive picker when you want to fuzzy-select a dest.
$_zoxide = Get-Command zoxide -ErrorAction SilentlyContinue
if ($_zoxide) {
    $cacheFile  = Join-Path $_cacheDir 'zoxide-init.ps1'
    $needsRegen = $true
    if (Test-Path $cacheFile) {
        try {
            $binTime   = (Get-Item -LiteralPath $_zoxide.Source -ErrorAction Stop).LastWriteTimeUtc
            $cacheTime = (Get-Item -LiteralPath $cacheFile      -ErrorAction Stop).LastWriteTimeUtc
            if ($cacheTime -gt $binTime) { $needsRegen = $false }
        } catch { }
    }
    if ($needsRegen) {
        zoxide init powershell --cmd cd | Set-Content -Path $cacheFile -Encoding UTF8
    }
    . $cacheFile
}

# --- Starship (must be last — overwrites the prompt function) ---------------
#  Config: the single shared shared/starship.toml in the clone.
$_starship = Get-Command starship -ErrorAction SilentlyContinue
if ($_starship) {
    $starshipConfig = Join-Path $global:NowhereRepoDir 'shared/starship.toml'
    if (Test-Path $starshipConfig) { $env:STARSHIP_CONFIG = $starshipConfig }

    $cacheFile  = Join-Path $_cacheDir 'starship-init.ps1'
    $needsRegen = $true
    if (Test-Path $cacheFile) {
        try {
            $binTime   = (Get-Item -LiteralPath $_starship.Source -ErrorAction Stop).LastWriteTimeUtc
            $cacheTime = (Get-Item -LiteralPath $cacheFile        -ErrorAction Stop).LastWriteTimeUtc
            if ($cacheTime -gt $binTime) { $needsRegen = $false }
        } catch { }
    }
    if ($needsRegen) {
        starship init powershell | Set-Content -Path $cacheFile -Encoding UTF8
    }
    . $cacheFile
}

Remove-Variable _cacheDir, _zoxide, _starship -ErrorAction SilentlyContinue
