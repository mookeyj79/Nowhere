# =============================================================================
#  Plan.ps1  (dot-source it)
#
#  The Windows install plan: what shared/tools.json and powershell/modules.json
#  ask for on a role. Reads files only and installs nothing. bootstrap.ps1 and
#  Sync-Pins.ps1 read this instead of interpreting the manifests themselves.
#
#    Get-NowherePlan -Role <devbox|server> -RepoRoot <clone>
#      one object per planned action, in manifest order:
#        Kind winget     Name, Id
#        Kind installer  Name, Installer        (uv: astral)
#        Kind uvtool     Name, Spec             (name==version or name @ source)
#        Kind module     Name, Version
#
#  The Linux plan is bootstrap/lib/plan.sh: same manifest, same spec rule.
# =============================================================================

function Get-NowherePlan {
    param(
        [Parameter(Mandatory)] [ValidateSet('devbox', 'server')] [string]$Role,
        [Parameter(Mandatory)] [string]$RepoRoot,
        [string]$ToolsPath = (Join-Path $RepoRoot 'shared/tools.json'),
        [string]$ModulesPath = (Join-Path $RepoRoot 'powershell/modules.json')
    )
    $manifest = Get-Content -LiteralPath $ToolsPath -Raw | ConvertFrom-Json
    $layers = if ($Role -eq 'devbox') { 'core', 'dev' } else { 'core' }
    foreach ($t in @($manifest.tools | Where-Object { $_.layer -in $layers })) {
        if ($t.packages.winget) { [pscustomobject]@{ Kind = 'winget'; Name = $t.name; Id = $t.packages.winget } }
        if ($t.installer) { [pscustomobject]@{ Kind = 'installer'; Name = $t.name; Installer = $t.installer } }
    }
    foreach ($u in @($manifest.uvTools | Where-Object { $_ -and $Role -in $_.roles })) {
        $spec = if ($u.source) { "$($u.name) @ $($u.source)" } else { "$($u.name)==$($u.version)" }
        [pscustomobject]@{ Kind = 'uvtool'; Name = $u.name; Spec = $spec }
    }
    if (Test-Path -LiteralPath $ModulesPath) {
        foreach ($m in @((Get-Content -LiteralPath $ModulesPath -Raw | ConvertFrom-Json).modules)) {
            [pscustomobject]@{ Kind = 'module'; Name = $m.name; Version = $m.version }
        }
    }
}
