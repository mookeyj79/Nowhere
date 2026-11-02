# =============================================================================
#  bootstrap.ps1 <devbox|server>
#
#  Readies a Windows machine for Nowhere. Safe to re-run: every step checks
#  state first and does nothing when already done.
#
#    1. winget tools from the install plan (lib/Plan.ps1: shared/tools.json,
#       core always, dev on devbox)
#    2. uv via Astral's official installer, only when not on PATH
#    3. pins (lib/Sync-Pins.ps1 -Strict): on a server, server-motd as a uv
#       tool at the manifest pin, its config.toml seeded from
#       shared/server-motd/config.toml.example; PowerShell modules from
#       powershell/modules.json at exact versions
#    4. stub at the profile path (a different existing stub is backed up)
#    5. local override seeded from local.ps1.example if missing, owner-only
#    6. git core.hooksPath = .githooks in this clone
#
#  Server editions without winget (Windows Server 2022 and older): step 1 is
#  skipped with a warning naming the tools to install by hand; everything
#  else, including uv and server-motd, still runs.
#
#  The -RepoRoot/-ProfilePath/-ConfigDir parameters exist for the sandbox tests.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('devbox', 'server')]
    [string]$Role,
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
    [string]$ConfigDir = (Join-Path $HOME '.config/nowhere'),
    [string]$MotdConfigDir = $(if ($env:ProgramData) { Join-Path $env:ProgramData 'server-motd' } else { Join-Path $HOME '.config/server-motd' })
)

$ErrorActionPreference = 'Stop'
function Step($msg) { Write-Host "==> $msg" }

# Copies $Source to $Dest only when $Dest is absent, then locks it to the current user.
function Copy-OwnerOnly($Source, $Dest) {
    if (Test-Path -LiteralPath $Dest) { return $false }
    New-Item -ItemType Directory -Path (Split-Path $Dest) -Force | Out-Null
    Copy-Item $Source $Dest
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $Dest
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($me, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $Dest -AclObject $acl
    } else {
        & chmod 600 $Dest
    }
    $true
}

# --- 1. Tools ----------------------------------------------------------------
. (Join-Path $RepoRoot 'bootstrap/lib/Plan.ps1')
$plan = @(Get-NowherePlan -Role $Role -RepoRoot $RepoRoot)
$winget = @($plan | Where-Object Kind -eq 'winget')

$haveWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if (-not $haveWinget) {
    $names = ($winget | ForEach-Object Name) -join ', '
    Write-Warning "winget not found; skipping tool install. Install by hand: $names (Windows Server 2025 ships winget; on 2022 and older install App Installer or use Repair-WinGetPackageManager)."
}
foreach ($tool in $winget) {
    if (-not $haveWinget) { break }
    & winget list --id $tool.Id --exact --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) { continue }
    Step "installing $($tool.Name) ($($tool.Id))"
    & winget install --id $tool.Id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install $($tool.Id) (exit $LASTEXITCODE)" }
}

# --- 2. uv (official installer, only when absent) ------------------------------
if (($plan | Where-Object { $_.Kind -eq 'installer' -and $_.Installer -eq 'astral' }) -and -not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Step 'installing uv (official installer)'
    Invoke-RestMethod 'https://astral.sh/uv/install.ps1' | Invoke-Expression
    # The installer edits the persistent PATH, not this session's.
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        $env:PATH = (Join-Path $HOME '.local/bin') + [IO.Path]::PathSeparator + $env:PATH
    }
}

# --- 3. Pins: uv tools (server-motd on servers) and PowerShell modules ----------
& (Join-Path $RepoRoot 'bootstrap/lib/Sync-Pins.ps1') -Role $Role -RepoRoot $RepoRoot -Strict

if (@($plan | Where-Object { $_.Kind -eq 'uvtool' -and $_.Name -eq 'server-motd' }).Count) {
    $motdCfg = Join-Path $MotdConfigDir 'config.toml'
    if (Copy-OwnerOnly (Join-Path $RepoRoot 'shared/server-motd/config.toml.example') $motdCfg) {
        Step "seeded $motdCfg (owner-only)"
    }
}

# --- 4. Stub -----------------------------------------------------------------
$entry = Join-Path $RepoRoot 'powershell/profile.ps1'
$stub = @"
# Nowhere stub (written by bootstrap.ps1). Logic lives in the clone.
`$env:NOWHERE_ROLE = '$Role'
. '$entry'
"@
$current = if (Test-Path -LiteralPath $ProfilePath) { Get-Content -LiteralPath $ProfilePath -Raw }
if ($null -eq $current -or $current.TrimEnd() -ne $stub.TrimEnd()) {
    New-Item -ItemType Directory -Path (Split-Path $ProfilePath) -Force | Out-Null
    if ($null -ne $current) {
        $bak = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Move-Item -LiteralPath $ProfilePath -Destination $bak
        Step "existing profile backed up to $bak"
    }
    Set-Content -LiteralPath $ProfilePath -Value $stub
    Step "wrote stub $ProfilePath"
}

# --- 5. Local override -------------------------------------------------------
$override = Join-Path $ConfigDir 'local.ps1'
if (Copy-OwnerOnly (Join-Path $RepoRoot 'powershell/local.ps1.example') $override) {
    Step "seeded $override (owner-only)"
}

# --- 6. Secrets hook ---------------------------------------------------------
& git -C $RepoRoot config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { throw 'git config core.hooksPath failed' }

Step "bootstrap complete ($Role)"
