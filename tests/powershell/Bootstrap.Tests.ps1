#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'Bootstrap.Sandbox.ps1')
    $script:Manifest = Get-Content (Join-Path $script:RepoRoot 'shared/tools.json') -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
}
AfterAll { Remove-BootstrapSandboxes }

Describe 'role argument' {
    It 'rejects an invalid role and changes nothing' {
        $sb = New-BootstrapSandbox
        $r = Invoke-Bootstrap $sb -Role laptop
        $r.ExitCode | Should -Not -Be 0
        Test-Path $sb.Profile | Should -BeFalse
        Read-Log $sb 'winget.log' | Should -BeNullOrEmpty
    }
}

Describe 'tool manifest' {
    It 'lists each tool once with a layer and a winget id; btop is btop4win' {
        $names = $script:Manifest.tools.name
        $names | Should -Not -BeNullOrEmpty
        ($names | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        foreach ($t in $script:Manifest.tools) { $t.layer | Should -BeIn 'core', 'dev' }
        ($script:Manifest.tools | Where-Object name -eq 'btop').packages.winget | Should -Be 'aristocratos.btop4win'
    }
}

Describe 'tool install' {
    It 'devbox installs core and dev tools via winget' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb -Role devbox).ExitCode | Should -Be 0
        $installed = Read-Log $sb 'installed.txt'
        foreach ($t in $script:Manifest.tools | Where-Object { $_.packages.winget }) {
            $installed | Should -Contain $t.packages.winget
        }
    }
    It 'server installs core tools only' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        $installed = Read-Log $sb 'installed.txt'
        $installed | Should -Contain 'Starship.Starship'
        $installed | Should -Not -Contain 'Kubernetes.kubectl'
    }
}

Describe 'pinned modules' {
    It 'the real manifest pins every module to an exact version' {
        $mods = (Get-Content (Join-Path $script:RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json).modules
        $mods | Should -Not -BeNullOrEmpty
        foreach ($m in $mods) { $m.version | Should -Match '^\d+(\.\d+){1,3}$' }
    }
    It 'installs each manifest module at its exact version' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        $mods = (Get-Content (Join-Path $sb.Clone 'powershell/modules.json') -Raw | ConvertFrom-Json).modules
        $mods | Should -Not -BeNullOrEmpty
        $log = Read-Log $sb 'modules.log'
        foreach ($m in $mods) {
            $log | Should -Contain "$($m.name) $($m.version)"
            Test-Path (Join-Path $sb.Root "modules/$($m.name)/$($m.version)") | Should -BeTrue
        }
    }
}

Describe 'uv' {
    It 'runs the official installer when uv is absent' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        Read-Log $sb 'irm.log' | Should -Be @('https://astral.sh/uv/install.ps1')
    }
    It 'does nothing when uv is already on PATH' {
        $sb = New-BootstrapSandbox -WithUv
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        Read-Log $sb 'irm.log' | Should -BeNullOrEmpty
    }
}

Describe 'stub' {
    It 'writes a stub that sets the role and sources the clone profile' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        $stub = Get-Content $sb.Profile -Raw
        $stub | Should -Match "NOWHERE_ROLE = 'server'"
        $stub | Should -Match ([regex]::Escape((Join-Path $sb.Clone 'powershell/profile.ps1')))
    }
    It 'backs up a different existing stub instead of overwriting it' {
        $sb = New-BootstrapSandbox
        Set-Content $sb.Profile 'my precious profile'
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        $bak = @(Get-ChildItem (Split-Path $sb.Profile) -Filter 'profile.ps1.bak-*')
        $bak | Should -HaveCount 1
        Get-Content $bak[0].FullName -Raw | Should -Match 'my precious profile'
        Get-Content $sb.Profile -Raw | Should -Match 'NOWHERE_ROLE'
    }
}

Describe 'local override' {
    It 'seeds from the example when missing, owner-only' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        $f = Join-Path $sb.Config 'local.ps1'
        Get-Content $f -Raw | Should -Be (Get-Content (Join-Path $sb.Clone 'powershell/local.ps1.example') -Raw)
        if ($IsWindows) {
            $acl = Get-Acl $f
            $acl.AreAccessRulesProtected | Should -BeTrue
            $acl.Access | Should -HaveCount 1
            $acl.Access[0].IdentityReference.Value | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
        } else {
            (& stat -c '%a' $f) | Should -Be '600'
        }
    }
    It 'leaves an existing override untouched' {
        $sb = New-BootstrapSandbox
        New-Item -ItemType Directory $sb.Config -Force | Out-Null
        $f = Join-Path $sb.Config 'local.ps1'
        Set-Content $f '$env:MY_TOKEN = "keep"'
        $before = (Get-Item $f).LastWriteTimeUtc
        $aclBefore = (Get-Acl $f).Sddl
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        Get-Content $f -Raw | Should -Match 'keep'
        (Get-Item $f).LastWriteTimeUtc | Should -Be $before
        (Get-Acl $f).Sddl | Should -Be $aclBefore
    }
}

Describe 'git hooks' {
    It 'sets core.hooksPath in the clone' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        (git -C $sb.Clone config core.hooksPath) | Should -Be '.githooks'
    }
}

Describe 'idempotence' {
    It 'a second run installs nothing, backs up nothing, rewrites nothing' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        $stubTime = (Get-Item $sb.Profile).LastWriteTimeUtc
        $installs = (Read-Log $sb 'installed.txt').Count
        $modInstalls = (Read-Log $sb 'modules.log').Count
        $installs | Should -BeGreaterThan 0
        (Invoke-Bootstrap $sb).ExitCode | Should -Be 0
        (Read-Log $sb 'installed.txt').Count | Should -Be $installs
        (Read-Log $sb 'modules.log').Count | Should -Be $modInstalls
        Read-Log $sb 'irm.log' | Should -HaveCount 1
        (Get-Item $sb.Profile).LastWriteTimeUtc | Should -Be $stubTime
        Get-ChildItem (Split-Path $sb.Profile) -Filter '*.bak-*' | Should -BeNullOrEmpty
    }
}
