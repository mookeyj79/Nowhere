#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

# Tool guards, dev-layer role gating and the missing-tools hint are rows of
# tests/parity.txt, run by Parity.Tests.ps1.

Describe 'dev alias layer' {
    It 'kns switches namespace through kubectl, mapping d to default' {
        $r = Invoke-NowhereSession -Role devbox -Tools kubectl -Probe 'kns d'
        ($r.Output -join ' ') | Should -Match 'namespace=default'
    }
}

Describe 'update' {
    It 'resolves to Update-System' {
        $r = Invoke-NowhereSession -Role server -Probe '(Get-Alias update).ResolvedCommand.Name'
        $r.Output | Should -Contain 'Update-System'
    }
    It 'Update-PSProfile brings modules to their pins and never runs winget' {
        $probe = 'function Get-Module { }; function Install-Module { "INSTALL $($args -join '' '')" }; Update-PSProfile'
        $r = Invoke-NowhereSession -Role devbox -Tools winget -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $pins = (Get-Content (Join-Path $script:RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json).modules
        foreach ($m in $pins) {
            ($r.Output -join "`n") | Should -Match "INSTALL -Name $($m.name) -RequiredVersion $([regex]::Escape($m.version))"
        }
        $r.Output | Where-Object { $_ -match '^winget ' } | Should -BeNullOrEmpty
    }
}

Describe 'shared Macchiato starship config' {
    It 'is Macchiato-only' {
        $toml = Get-Content -Raw (Join-Path $script:RepoRoot 'shared/starship.toml')
        $toml | Should -Match "palette\s*=\s*'catppuccin_macchiato'"
        $toml | Should -Not -Match 'catppuccin_(mocha|frappe|latte)'
    }
    It 'is the config PowerShell uses when starship is present' {
        $r = Invoke-NowhereSession -Role server -Tools starship -Probe '"cfg=$env:STARSHIP_CONFIG"'
        ($r.Output -join "`n") | Should -Match 'cfg=.*shared[\\/]starship\.toml'
    }
}

Describe 'cached init' {
    It 'caches the generated script under the cache dir and dot-sources it' {
        $probe = '$f = Join-Path $global:NowhereCacheDir ''starship-init.ps1''; "cached=" + (Get-Content $f -Raw).Trim()'
        $r = Invoke-NowhereSession -Role server -Tools starship -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'cached=starship init powershell'
        # the cached script ran: the shim's echo of its own arguments
        $r.Output | Should -Contain 'starship init powershell'
    }
    It 'regenerates only when the binary is newer than the cache' {
        $probe = @'
$b = (Get-Command starship -CommandType Application).Source
$f = Join-Path $global:NowhereCacheDir 'starship-init.ps1'
Set-Content $f "'warm'"; (Get-Item $b).LastWriteTimeUtc = [datetime]'2000-01-01'
$null = Get-NowhereCachedInit starship-init starship @('init', 'powershell'); "old-bin=" + (Get-Content $f -Raw).Trim()
(Get-Item $b).LastWriteTimeUtc = [datetime]'2099-01-01'
$null = Get-NowhereCachedInit starship-init starship @('init', 'powershell'); "new-bin=" + (Get-Content $f -Raw).Trim()
'@
        $r = Invoke-NowhereSession -Role server -Tools starship -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain "old-bin='warm'"
        $r.Output | Should -Contain 'new-bin=starship init powershell'
    }
    It 'a failing generator caches nothing; empty output is cached' {
        $probe = @'
$d = Join-Path $HOME 'gen'; $null = New-Item -ItemType Directory $d
if ($IsWindows) {
    Set-Content (Join-Path $d 'broken.cmd') '@echo $global:Broken = 1& @exit /b 1'
    Set-Content (Join-Path $d 'quiet.cmd') '@exit /b 0'
} else {
    Set-Content (Join-Path $d 'broken') "#!/bin/sh`necho '`$global:Broken = 1'`nexit 1"
    Set-Content (Join-Path $d 'quiet') "#!/bin/sh`nexit 0"
    foreach ($f in 'broken', 'quiet') { [IO.File]::SetUnixFileMode((Join-Path $d $f), 'UserRead, UserWrite, UserExecute') }
}
$env:PATH = $d + [IO.Path]::PathSeparator + $env:PATH
"broken=[" + (Get-NowhereCachedInit broken-init broken) + "]"
"broken-cached=" + (Test-Path (Join-Path $global:NowhereCacheDir 'broken-init.ps1'))
"quiet-cached=" + [bool](Get-NowhereCachedInit quiet-init quiet)
'@
        $r = Invoke-NowhereSession -Role server -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'broken=[]'
        $r.Output | Should -Contain 'broken-cached=False'
        $r.Output | Should -Contain 'quiet-cached=True'
    }
    It 'an absent tool gives no script and no error' {
        $r = Invoke-NowhereSession -Role server -Probe '"r=[" + (Get-NowhereCachedInit zoxide-init zoxide @(''init'')) + "]"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'r=[]'
    }
}

Describe 'missing tools' {
    It 'every core tool in shared/core-tools.txt is a core tool in the manifest' {
        $core = ((Get-Content (Join-Path $script:RepoRoot 'shared/tools.json') -Raw | ConvertFrom-Json).tools |
            Where-Object layer -eq 'core').name
        foreach ($t in Get-NowhereCoreToolList) { $core | Should -Contain $t }
    }
}
