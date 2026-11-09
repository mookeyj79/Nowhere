# =============================================================================
#  Sync-Pins.ps1 -Role <devbox|server> [-RepoRoot <clone>] [-Strict]
#
#  Brings a Windows machine to the pins in its plan (Plan.ps1):
#    uvtool   uv tools at their pinned spec (server-motd on a server)
#    module   PowerShell modules at exactly their pinned version
#  Anything already at its pin is left alone, so it is safe to run any number
#  of times. bootstrap.ps1 runs it with -Strict (throw at the first failure);
#  Update-System and Update-PSProfile run it without (warn about each failure,
#  carry on, exit 1 at the end if any failed).
#
#  The Linux counterpart is bootstrap/lib/pins.sh.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('devbox', 'server')] [string]$Role,
    [string]$RepoRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [switch]$Strict
)

. (Join-Path $PSScriptRoot 'Plan.ps1')
. (Join-Path $PSScriptRoot 'UvToolPin.ps1')
$script:failed = $false
function Fail([string]$Message) {
    if ($Strict) { throw $Message }
    Write-Warning $Message
    $script:failed = $true
}

$plan = @(Get-NowherePlan -Role $Role -RepoRoot $RepoRoot)

foreach ($t in @($plan | Where-Object Kind -eq 'uvtool')) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        if ($Strict) { Fail "uv not found; cannot install $($t.Name)" }
        else { Write-Host "uv not found, skipping $($t.Name) (run bootstrap)" }
        continue
    }
    $listed = @(& uv tool list --show-version-specifiers 2>$null)
    if (Test-NowhereUvToolPinned -Spec $t.Spec -Listed $listed) { continue }
    Write-Host "==> installing $($t.Spec) (uv tool)"
    & uv tool install $t.Spec
    if ($LASTEXITCODE -ne 0) { Fail "uv tool install $($t.Name) failed (exit $LASTEXITCODE)" }
}

foreach ($m in @($plan | Where-Object Kind -eq 'module')) {
    $have = Get-Module -ListAvailable -Name $m.Name | Where-Object { $_.Version -eq [version]$m.Version }
    if ($have) { continue }
    Write-Host "==> installing module $($m.Name) $($m.Version)"
    try {
        $ErrorActionPreference = 'Stop'
        Install-Module -Name $m.Name -RequiredVersion $m.Version -Scope CurrentUser -Force -AllowClobber
    } catch {
        Fail "module $($m.Name) $($m.Version) could not be installed: $_"
    } finally {
        $ErrorActionPreference = 'Continue'
    }
}

if ($script:failed) { exit 1 }
