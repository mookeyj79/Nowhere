#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# The Windows install plan (bootstrap/lib/Plan.ps1) and pin reconcile
# (bootstrap/lib/Sync-Pins.ps1), against fixture manifests.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $script:RepoRoot 'bootstrap/lib/Plan.ps1')
    $script:Sync = Join-Path $script:RepoRoot 'bootstrap/lib/Sync-Pins.ps1'
    # Pester mocks only commands that exist; PowerShellGet is not on every host.
    if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
        function global:Install-Module { param($Name, $RequiredVersion, $Scope, [switch]$Force, [switch]$AllowClobber) }
        $script:DefinedInstallModule = $true
    }

    function New-PlanFixture {
        param([object[]]$Modules = @(@{ name = 'HaveIt'; version = '1.0.0' }, @{ name = 'NeedIt'; version = '2.0.0' }))
        $d = Join-Path ([IO.Path]::GetTempPath()) ('nowhere-plan-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $d 'shared'), (Join-Path $d 'powershell') -Force | Out-Null
        Set-Content (Join-Path $d 'shared/tools.json') @'
{ "tools": [
    { "name": "corewg", "layer": "core", "packages": { "winget": "W.Core", "apt": "core" } },
    { "name": "devwg",  "layer": "dev",  "packages": { "winget": "W.Dev" } },
    { "name": "aptonly", "layer": "core", "packages": { "apt": "aptonly" } },
    { "name": "uv",     "layer": "core", "installer": "astral", "packages": {} }
  ],
  "uvTools": [
    { "name": "bysource",  "source": "git+https://x/y@0123", "roles": ["server"] },
    { "name": "byversion", "version": "0.9.1", "roles": ["server", "devbox"] }
  ] }
'@
        Set-Content (Join-Path $d 'powershell/modules.json') (@{ modules = $Modules } | ConvertTo-Json -Depth 3)
        $d
    }

    # A uv on PATH that logs its arguments and lists nothing as installed.
    function New-UvShim {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('nowhere-uv-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        if ($IsWindows) { Set-Content (Join-Path $d 'uv.cmd') "@echo %*>> `"%~dp0uv.log`"" }
        else {
            Set-Content (Join-Path $d 'uv') "#!/bin/sh`necho `"`$*`" >> `"`$(dirname `"`$0`")/uv.log`""
            chmod +x (Join-Path $d 'uv')
        }
        $d
    }
}

AfterAll {
    if ($script:DefinedInstallModule) { Remove-Item function:global:Install-Module -ErrorAction SilentlyContinue }
}

Describe 'Get-NowherePlan' {
    BeforeAll { $script:Fx = New-PlanFixture }
    AfterAll { Remove-Item $script:Fx -Recurse -Force -ErrorAction SilentlyContinue }

    It 'layers: core everywhere, dev on a devbox only' {
        $server = Get-NowherePlan -Role server -RepoRoot $script:Fx
        $devbox = Get-NowherePlan -Role devbox -RepoRoot $script:Fx
        ($server | Where-Object Kind -eq 'winget').Id | Should -Be @('W.Core')
        ($devbox | Where-Object Kind -eq 'winget').Id | Should -Be @('W.Core', 'W.Dev')
    }
    It 'plans the uv installer and skips tools with no winget package' {
        $plan = Get-NowherePlan -Role server -RepoRoot $script:Fx
        ($plan | Where-Object Kind -eq 'installer').Installer | Should -Be 'astral'
        $plan.Name | Should -Not -Contain 'aptonly'
    }
    It 'uv tool specs: by role, from source or version' {
        (Get-NowherePlan -Role server -RepoRoot $script:Fx | Where-Object Kind -eq 'uvtool').Spec |
            Should -Be @('bysource @ git+https://x/y@0123', 'byversion==0.9.1')
        (Get-NowherePlan -Role devbox -RepoRoot $script:Fx | Where-Object Kind -eq 'uvtool').Spec |
            Should -Be @('byversion==0.9.1')
    }
    It 'plans every pinned module at its version' {
        $m = Get-NowherePlan -Role devbox -RepoRoot $script:Fx | Where-Object Kind -eq 'module'
        $m | ForEach-Object { "$($_.Name) $($_.Version)" } | Should -Be @('HaveIt 1.0.0', 'NeedIt 2.0.0')
    }
    It 'plans the shipped manifests on both roles' {
        foreach ($role in 'devbox', 'server') {
            $plan = @(Get-NowherePlan -Role $role -RepoRoot $script:RepoRoot)
            $plan.Count | Should -BeGreaterThan 0
            ($plan | Where-Object Kind -eq 'module').Count | Should -BeGreaterThan 0
        }
        (Get-NowherePlan -Role server -RepoRoot $script:RepoRoot | Where-Object Kind -eq 'uvtool').Name | Should -Contain 'server-motd'
    }
}

Describe 'Test-NowhereUvToolPinned' {
    It 'matches a source pin only at that source' {
        $spec = 'tool @ git+https://x/y@aaa'
        Test-NowhereUvToolPinned -Spec $spec -Listed @('tool v0.1.0 [required:  git+https://x/y@aaa]') | Should -BeTrue
        Test-NowhereUvToolPinned -Spec $spec -Listed @('tool v0.1.0 [required:  git+https://x/y@bbb]') | Should -BeFalse
        Test-NowhereUvToolPinned -Spec $spec -Listed @('other v0.1.0 [required:  git+https://x/y@aaa]') | Should -BeFalse
    }
    It 'matches a version pin exactly' {
        Test-NowhereUvToolPinned -Spec 'tool==1.2' -Listed @('tool v1.2 [required: ==1.2]') | Should -BeTrue
        Test-NowhereUvToolPinned -Spec 'tool==1.2' -Listed @('tool v1.2.1 [required: ==1.2.1]') | Should -BeFalse
        Test-NowhereUvToolPinned -Spec 'tool==1.2' -Listed @() | Should -BeFalse
    }
}

Describe 'Sync-Pins' {
    # Every test gets the uv shim first on PATH: the real uv is never reached.
    BeforeEach {
        $script:Fx = New-PlanFixture
        $script:UvDir = New-UvShim
        $script:SavedPath = $env:PATH
        $env:PATH = $script:UvDir + [IO.Path]::PathSeparator + $env:PATH
    }
    AfterEach {
        $env:PATH = $script:SavedPath
        Remove-Item $script:Fx, $script:UvDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'installs exactly the missing pinned modules, never floating' {
        Mock Get-Module { if ($Name -eq 'HaveIt') { [pscustomobject]@{ Version = [version]'1.0.0' } } }
        Mock Install-Module { }
        & $script:Sync -Role devbox -RepoRoot $script:Fx 6> $null
        Should -Invoke Install-Module -Times 1 -Exactly
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'NeedIt' -and $RequiredVersion -eq '2.0.0' }
    }
    It 'leniently reports a failed install and carries on, exit 1' {
        Mock Get-Module { }
        Mock Install-Module { if ($Name -eq 'HaveIt') { throw 'boom' } }
        $warn = & $script:Sync -Role devbox -RepoRoot $script:Fx 3>&1 6> $null
        $LASTEXITCODE | Should -Be 1
        "$warn" | Should -Match 'HaveIt'
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'NeedIt' }
    }
    It 'strictly stops at the first failure' {
        Mock Get-Module { }
        Mock Install-Module { throw 'boom' }
        { & $script:Sync -Role devbox -RepoRoot $script:Fx -Strict 6> $null } | Should -Throw '*HaveIt*'
    }
    Context 'uv tools' {
        BeforeEach {
            Mock Get-Module { [pscustomobject]@{ Version = [version]'1.0.0' } }
            Mock Install-Module { }
        }
        It 'installs each planned uv tool for the role' {
            & $script:Sync -Role server -RepoRoot $script:Fx 6> $null
            $log = Get-Content (Join-Path $script:UvDir 'uv.log')
            ($log -join "`n") | Should -Match 'tool install "?bysource @ git\+https://x/y@0123'
            ($log -join "`n") | Should -Match 'tool install "?byversion==0\.9\.1'
        }
        It 'skips uv tools quietly when uv is absent (lenient)' {
            $env:PATH = @($script:SavedPath -split [IO.Path]::PathSeparator | Where-Object {
                    $_ -and -not (Test-Path (Join-Path $_ 'uv.exe')) -and -not (Test-Path (Join-Path $_ 'uv'))
                }) -join [IO.Path]::PathSeparator
            $global:LASTEXITCODE = 0
            $out = & $script:Sync -Role server -RepoRoot $script:Fx 6>&1
            $LASTEXITCODE | Should -Not -Be 1
            "$out" | Should -Match 'uv not found'
        }
    }
}
