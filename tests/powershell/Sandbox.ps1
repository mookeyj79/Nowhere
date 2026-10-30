# Sandbox seam: run a real pwsh session against a throwaway HOME, through a
# stub that sets NOWHERE_ROLE and dot-sources the profile from this clone.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Invoke-NowhereSession {
    param(
        [string]$Role,
        [string]$Probe = '',
        [string]$LocalOverride,
        # Restrict PATH to the pwsh directory plus shims for exactly these tools.
        # Each shim echoes its own name and arguments.
        [string[]]$Tools
    )
    $sandbox = Join-Path ([IO.Path]::GetTempPath()) ('nowhere-' + [guid]::NewGuid().ToString('N'))
    $home_ = Join-Path $sandbox 'home'
    $cfg   = Join-Path $home_ '.config/nowhere'
    New-Item -ItemType Directory -Path $cfg, (Join-Path $home_ 'AppData/Local'), (Join-Path $sandbox 'xdg') -Force | Out-Null
    if ($PSBoundParameters.ContainsKey('LocalOverride')) {
        Set-Content -Path (Join-Path $cfg 'local.ps1') -Value $LocalOverride
    }
    $restrictPath = $null
    if ($PSBoundParameters.ContainsKey('Tools')) {
        $bin = Join-Path $sandbox 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        foreach ($t in $Tools) {
            if ($IsWindows) {
                Set-Content -Path (Join-Path $bin "$t.cmd") -Value "@echo $t %*"
            } else {
                $f = Join-Path $bin $t
                Set-Content -Path $f -Value "#!/bin/sh`necho $t `"`$@`""
                chmod +x $f
            }
        }
        $restrictPath = $bin + [IO.Path]::PathSeparator + (Split-Path (Get-Process -Id $PID).Path)
    }
    $stub = Join-Path $home_ 'stub.ps1'
    $roleLine = if ($Role) { "`$env:NOWHERE_ROLE = '$Role'" } else { '' }
    Set-Content -Path $stub -Value @($roleLine, ". '$(Join-Path $script:RepoRoot 'powershell/profile.ps1')'")

    $vars = @{
        HOME = $home_; USERPROFILE = $home_; LOCALAPPDATA = (Join-Path $home_ 'AppData/Local')
        XDG_CONFIG_HOME = (Join-Path $home_ '.config'); XDG_CACHE_HOME = (Join-Path $sandbox 'xdg')
        XDG_DATA_HOME = (Join-Path $sandbox 'xdg'); NOWHERE_ROLE = $null; NOWHERE_HOME = $null
        CONFCRYPT_HOME = $null; EDITOR = $null; VISUAL = $null
    }
    if ($restrictPath) { $vars['PATH'] = $restrictPath }
    $saved = @{}
    foreach ($k in $vars.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $vars[$k])
    }
    try {
        $pwsh = (Get-Process -Id $PID).Path
        $out = & $pwsh -NoProfile -NoLogo -NonInteractive -Command ". '$stub'; $Probe" 2>&1
        $code = $LASTEXITCODE
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    [pscustomobject]@{
        ExitCode = $code
        Output   = @($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
        Errors   = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    }
}
