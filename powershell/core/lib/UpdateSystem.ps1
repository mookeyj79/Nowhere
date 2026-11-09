# =============================================================================
#  UpdateSystem.ps1  (dot-source it)
#
#  The decisions inside Update-System, kept apart from the admin-only script
#  so they can be tested with fixture text instead of a real machine:
#
#    Resolve-UpdateSteps -Role -Requested -HaveWinget
#      which steps a run performs, in order: Windows, Winget, Tools, WSL,
#      DiskCleanup. Nothing requested means every step on a devbox; on a
#      server, Windows Update and Tools, plus Winget when winget exists (WSL
#      is not a server feature and cleanmgr needs Desktop Experience).
#
#    ConvertFrom-WingetUpgradeTable -Lines
#      `winget upgrade` output (spinner redraws and all) to {Name, Id}, one
#      per upgradable package. winget has no JSON output for `upgrade`, so the
#      table is cut by the header's column positions (names and ids can hold
#      spaces).
#
#    Get-WingetFailureReason -Lines -ExitCode
#      $null when one package's upgrade succeeded (or had nothing applicable),
#      else a one-line reason taken from its output.
#
#    Invoke-NowhereToolsUpdate -Role -RepoRoot
#      the Tools step: uv self update, then the pins (bootstrap/lib/Sync-Pins.ps1).
# =============================================================================

$script:UpdateStepOrder = 'Windows', 'Winget', 'Tools', 'WSL', 'DiskCleanup'

function Resolve-UpdateSteps {
    param(
        [ValidateSet('devbox', 'server')] [string]$Role = 'server',
        [AllowEmptyCollection()] [string[]]$Requested = @(),
        [bool]$HaveWinget = $true
    )
    $want = if ($Requested.Count) { $Requested }
            elseif ($Role -eq 'server') { @('Windows', 'Tools') + @(if ($HaveWinget) { 'Winget' }) }
            else { $script:UpdateStepOrder }
    @($script:UpdateStepOrder | Where-Object { $_ -in $want })
}

# winget redraws its spinner with carriage returns; keep only the final redraw.
function Get-WingetCleanLine([string]$Line) { ($Line -split "`r")[-1].Trim() }

function ConvertFrom-WingetUpgradeTable {
    param([AllowEmptyCollection()] [AllowNull()] [string[]]$Lines = @())
    $clean = @($Lines | ForEach-Object { Get-WingetCleanLine $_ })
    $hdr = $clean | Where-Object { $_ -match '^Name\s+Id\s+Version\s+Available' } | Select-Object -First 1
    if (-not $hdr) { return }
    $idCol = $hdr.IndexOf('Id')
    $verCol = $hdr.IndexOf('Version')
    $slice = {
        param($l, $from, $to)
        if ($l.Length -le $from) { return '' }
        $l.Substring($from, [Math]::Min($to, $l.Length) - $from).Trim()
    }
    $inTable = $false
    foreach ($line in $clean) {
        if ($line -eq $hdr) { $inTable = $true; continue }
        if (-not $inTable -or $line -match '^-+$' -or -not $line) { continue }
        if ($line -match '^\d+ upgrades? available' -or $line -match 'have pins that prevent upgrade') { break }
        $id = & $slice $line $idCol $verCol
        if (-not $id) { continue }
        [pscustomobject]@{ Name = (& $slice $line 0 $idCol); Id = $id }
    }
}

function Get-WingetFailureReason {
    param([AllowEmptyCollection()] [AllowNull()] [string[]]$Lines = @(), [int]$ExitCode)
    # -1978335189 = "no applicable upgrade": --include-unknown version-mismatch
    # noise (e.g. Ubisoft Connect). Not a failure.
    if ($ExitCode -eq 0 -or $ExitCode -eq -1978335189) { return $null }
    [string[]]$out = @($Lines | ForEach-Object { Get-WingetCleanLine $_ } | Where-Object { $_ })
    # The reason starts at the first error-looking line; take it plus up to two
    # following lines and fold them into one (e.g. "An unexpected error occurred...
    # Download request status is not success. 0x80190193 : Forbidden (403).").
    $first = [array]::FindIndex($out, [Predicate[string]] { param($l) $l -match 'fail|error|forbidden|0x[0-9a-f]{8}' })
    if ($first -lt 0) { return "exit code $ExitCode" }
    $out[$first..([Math]::Min($first + 2, $out.Count - 1))] -join ' '
}

function Invoke-NowhereToolsUpdate {
    param(
        [ValidateSet('devbox', 'server')] [string]$Role = 'server',
        [Parameter(Mandatory)] [string]$RepoRoot
    )
    if (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue) {
        uv self update
        if ($LASTEXITCODE -ne 0) { Write-Warning 'uv self update failed' }
    } else {
        Write-Host 'uv not found, skipping uv self update (run bootstrap)'
    }
    & (Join-Path $RepoRoot 'bootstrap/lib/Sync-Pins.ps1') -Role $Role -RepoRoot $RepoRoot
}
