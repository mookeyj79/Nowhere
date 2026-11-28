# Sandbox seam for bootstrap.ps1: run it in a child pwsh against a throwaway
# HOME and clone, with a faked winget on PATH, a faked Install-Module and a
# faked Invoke-RestMethod. No network, no admin, no real machine state touched.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

$script:Sandboxes = @()

# Fake uv: records every call, remembers `uv tool install name==ver` or
# `uv tool install "name @ source"` in uvtools.txt and lists it back as
# "name vX [required: <pin>]" like the real `uv tool list --show-version-specifiers`.
$script:FakeUv = @'
$dir = $PSScriptRoot
Add-Content (Join-Path $dir 'uv.log') ($args -join ' ')
$state = Join-Path $dir 'uvtools.txt'
if ($args[0] -eq 'tool' -and $args[1] -eq 'install') {
    if ($args[2] -like '* @ *') {
        $n, $src = $args[2] -split ' @ ', 2
        $line = "$n v0.1.0 [required:  $src]"
    } else {
        $n, $v = $args[2] -split '=='
        $line = "$n v$v [required: ==$v]"
    }
    $kept = if (Test-Path $state) { @(Get-Content $state | Where-Object { $_ -notlike "$n v*" }) } else { @() }
    Set-Content $state (@($kept) + $line)
}
elseif ($args[0] -eq 'tool' -and $args[1] -eq 'list') {
    if (Test-Path $state) { Get-Content $state }
}
exit 0
'@

function Remove-BootstrapSandboxes {
    foreach ($r in $script:Sandboxes) { Remove-Item $r -Recurse -Force -ErrorAction SilentlyContinue }
    $script:Sandboxes = @()
}

function New-BootstrapSandbox {
    param([switch]$WithUv, [switch]$NoWinget)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('nowhere-bs-' + [guid]::NewGuid().ToString('N'))
    $bin  = Join-Path $root 'fakebin'
    $clone = Join-Path $root 'clone'
    New-Item -ItemType Directory -Path $bin, (Join-Path $root 'home'), (Join-Path $root 'modules'), $clone -Force | Out-Null

    # Fake winget: records every call, remembers installs in installed.txt.
    if (-not $NoWinget) { Set-Content (Join-Path $bin 'winget.ps1') @'
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
'@ }
    if ($WithUv) { Set-Content (Join-Path $bin 'uv.ps1') $script:FakeUv }

    # A minimal clone: the real bootstrap, manifests and example, in a fresh git repo.
    foreach ($p in 'bootstrap', 'shared/tools.json', 'shared/server-motd', 'powershell/local.ps1.example', 'powershell/modules.json', '.githooks') {
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
                       Profile = (Join-Path $root 'home/profile.ps1'); MotdConfig = (Join-Path $root 'programdata/server-motd'); Config = (Join-Path $root 'home/.config/nowhere') }
}

# The child's PATH: the fake bin, then pwsh's and git's directories. On Linux
# those are often /usr/bin, which can hold a distro uv that bootstrap would find
# instead of the fake (skipping the installer, running real `uv tool install`s).
# A host directory holding a uv is replaced by a mirror of links to its other
# entries, so the only uv in reach is the fake one.
$script:HostUvNames = 'uv', 'uvx', 'uv.exe', 'uvx.exe', 'uv.cmd', 'uv.ps1'
function Get-SandboxPath {
    param($Sandbox)
    $hostDirs = @((Split-Path (Get-Process -Id $PID).Path), (Split-Path (Get-Command git).Source)) | Select-Object -Unique
    $mirror = Join-Path $Sandbox.Root 'hostbin'
    $dirs = foreach ($d in $hostDirs) {
        if (-not ($script:HostUvNames | Where-Object { Test-Path (Join-Path $d $_) })) { $d; continue }
        if ($IsWindows) { throw "uv found in $d, which the bootstrap sandbox needs on PATH; it would shadow the fake uv" }
        New-Item -ItemType Directory -Path $mirror -Force | Out-Null
        # first link wins on a duplicate name; ln reports it and goes on
        & /bin/sh -c 'ln -s "$1"/* "$2"/ 2> /dev/null; true' sh $d $mirror
        foreach ($n in $script:HostUvNames) { Remove-Item (Join-Path $mirror $n) -Force -ErrorAction SilentlyContinue }
        $mirror
    }
    @($Sandbox.Bin) + @($dirs | Select-Object -Unique) -join [IO.Path]::PathSeparator
}

function Invoke-Bootstrap {
    param($Sandbox, [string]$Role = 'devbox')
    $pwsh = (Get-Process -Id $PID).Path
    $path = Get-SandboxPath $Sandbox
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
    Set-Content (Join-Path $env:FAKE_BIN 'uv.ps1') $env:FAKE_UV_BODY
    '$null'
}
'@
    $script = Join-Path $Sandbox.Clone 'bootstrap/bootstrap.ps1'
    $cmd = "$fakes`n& '$script' '$Role' -RepoRoot '$($Sandbox.Clone)' -ProfilePath '$($Sandbox.Profile)' -ConfigDir '$($Sandbox.Config)' -MotdConfigDir '$($Sandbox.MotdConfig)'"
    $vars = @{ PATH = $path; HOME = $Sandbox.Home; USERPROFILE = $Sandbox.Home; FAKE_BIN = $Sandbox.Bin
               FAKE_MODULES = $modDir; FAKE_UV_BODY = $script:FakeUv; PSModulePath = $modDir }
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
