# Sandbox seam for bootstrap.ps1: run it in a child pwsh against a throwaway
# HOME and clone, with a faked winget on PATH, a faked Install-Module and a
# faked Invoke-RestMethod. No network, no admin, no real machine state touched.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$script:Sandboxes = @()
function Remove-BootstrapSandboxes {
    foreach ($r in $script:Sandboxes) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    $script:Sandboxes = @()
}

function New-BootstrapSandbox {
    param([switch]$WithUv)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('nowhere-bs-' + [guid]::NewGuid().ToString('N'))
    $bin  = Join-Path $root 'fakebin'
    $clone = Join-Path $root 'clone'
    New-Item -ItemType Directory -Path $bin, (Join-Path $root 'home'), (Join-Path $root 'modules'), $clone -Force | Out-Null

    # Fake winget: records every call, remembers installs in installed.txt.
    Set-Content (Join-Path $bin 'winget.ps1') @'
$dir = $PSScriptRoot
Add-Content (Join-Path $dir 'winget.log') ($args -join ' ')
$i = [array]::IndexOf($args, '--id')
$id = if ($i -ge 0) { $args[$i + 1] }
$state = Join-Path $dir 'installed.txt'
switch ($args[0]) {
    'list'    { if ((Test-Path $state) -and ((Get-Content $state) -contains $id)) { exit 0 } else { exit 1 } }
    'install' { Add-Content $state $id; exit 0 }
    default   { exit 0 }
}
'@
    if ($WithUv) { Set-Content (Join-Path $bin 'uv.ps1') '' }

    # A minimal clone: the real bootstrap, manifests and example, in a fresh git repo.
    foreach ($p in 'bootstrap', 'shared/tools.json', 'powershell/local.ps1.example', 'powershell/modules.json', '.githooks') {
        $src = Join-Path $script:RepoRoot $p
        if (Test-Path $src) {
            $dst = Join-Path $clone $p
            New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
            Copy-Item $src $dst -Recurse -Force
        }
    }
    # Swap in fake module names: pwsh always re-adds the real user/system module
    # paths, so real names could already be installed on the test machine.
    Set-Content (Join-Path $clone 'powershell/modules.json') '{"modules":[{"name":"NowhereFakeModA","version":"1.2.3"},{"name":"NowhereFakeModB","version":"4.5.6.7"}]}'
    git -C $clone init -q 2>&1 | Out-Null
    $script:Sandboxes += $root
    [pscustomobject]@{ Root = $root; Bin = $bin; Clone = $clone; Home = (Join-Path $root 'home')
                       Profile = (Join-Path $root 'home/profile.ps1'); Config = (Join-Path $root 'home/.config/nowhere') }
}

function Invoke-Bootstrap {
    param($Sandbox, [string]$Role = 'devbox')
    $pwsh = (Get-Process -Id $PID).Path
    $gitDir = Split-Path (Get-Command git).Source
    $path = @($Sandbox.Bin, (Split-Path $pwsh), $gitDir) -join [IO.Path]::PathSeparator
    $modDir = Join-Path $Sandbox.Root 'modules'
    $fakes = @'
function Install-Module {
    param($Name, $RequiredVersion, [switch]$Force, $Scope, [switch]$AllowClobber, $Repository)
    Add-Content (Join-Path $env:FAKE_BIN 'modules.log') "$Name $RequiredVersion"
    $d = Join-Path $env:FAKE_MODULES "$Name/$RequiredVersion"
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    New-ModuleManifest -Path (Join-Path $d "$Name.psd1") -ModuleVersion $RequiredVersion
}
function Invoke-RestMethod {
    param($Uri)
    Add-Content (Join-Path $env:FAKE_BIN 'irm.log') "$Uri"
    'Set-Content (Join-Path $env:FAKE_BIN "uv.ps1") ""'
}
'@
    $script = Join-Path $Sandbox.Clone 'bootstrap/bootstrap.ps1'
    $cmd = "$fakes`n& '$script' '$Role' -RepoRoot '$($Sandbox.Clone)' -ProfilePath '$($Sandbox.Profile)' -ConfigDir '$($Sandbox.Config)'"
    $vars = @{ PATH = $path; HOME = $Sandbox.Home; USERPROFILE = $Sandbox.Home; FAKE_BIN = $Sandbox.Bin
               FAKE_MODULES = $modDir; PSModulePath = $modDir }
    $saved = @{}
    foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $vars[$k]) }
    try {
        $out = & $pwsh -NoProfile -NoLogo -NonInteractive -Command $cmd 2>&1
        $code = $LASTEXITCODE
    } finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    [pscustomobject]@{ ExitCode = $code; Output = @($out | ForEach-Object { "$_" }) }
}

function Read-Log {
    param($Sandbox, $Name)
    $f = Join-Path $Sandbox.Bin $Name
    if (Test-Path $f) { @(Get-Content $f) } else { @() }
}
