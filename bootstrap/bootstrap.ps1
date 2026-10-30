# =============================================================================
#  bootstrap.ps1 <devbox|server>
#
#  Readies a Windows machine for Nowhere. Safe to re-run: every step checks
#  state first and does nothing when already done.
#
#    1. tools from shared/tools.json via winget (core always, dev on devbox)
#    2. uv via Astral's official installer, only when not on PATH
#    3. PowerShell modules from powershell/modules.json at exact versions
#    4. stub at the profile path (a different existing stub is backed up)
#    5. local override seeded from local.ps1.example if missing, owner-only
#    6. git core.hooksPath = .githooks in this clone
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
    [string]$ConfigDir = (Join-Path $HOME '.config/nowhere')
)

$ErrorActionPreference = 'Stop'
function Step($msg) { Write-Host "==> $msg" }

# --- 1. Tools ----------------------------------------------------------------
$manifest = Get-Content (Join-Path $RepoRoot 'shared/tools.json') -Raw | ConvertFrom-Json
$layers = if ($Role -eq 'devbox') { 'core', 'dev' } else { 'core' }
$tools = $manifest.tools | Where-Object { $_.layer -in $layers }

foreach ($tool in $tools) {
    $id = $tool.packages.winget
    if (-not $id) { continue }
    & winget list --id $id --exact --accept-source-agreements *> $null
    if ($LASTEXITCODE -eq 0) { continue }
    Step "installing $($tool.name) ($id)"
    & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install $id (exit $LASTEXITCODE)" }
}

# --- 2. uv (official installer, only when absent) ------------------------------
if (($tools | Where-Object installer -eq 'astral') -and -not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Step 'installing uv (official installer)'
    Invoke-RestMethod 'https://astral.sh/uv/install.ps1' | Invoke-Expression
}

# --- 3. Pinned modules -------------------------------------------------------
$modules = (Get-Content (Join-Path $RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json).modules
foreach ($m in $modules) {
    $have = Get-Module -ListAvailable -Name $m.name | Where-Object { $_.Version -eq [version]$m.version }
    if ($have) { continue }
    Step "installing module $($m.name) $($m.version)"
    Install-Module -Name $m.name -RequiredVersion $m.version -Scope CurrentUser -Force -AllowClobber
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
if (-not (Test-Path -LiteralPath $override)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'powershell/local.ps1.example') $override
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $override
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($me, 'FullControl', 'Allow'))
        Set-Acl -LiteralPath $override -AclObject $acl
    } else {
        & chmod 600 $override
    }
    Step "seeded $override (owner-only)"
}

# --- 6. Secrets hook ---------------------------------------------------------
& git -C $RepoRoot config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { throw 'git config core.hooksPath failed' }

Step "bootstrap complete ($Role)"
