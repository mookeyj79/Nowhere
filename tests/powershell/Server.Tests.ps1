#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'Bootstrap.Sandbox.ps1')
    . (Join-Path $PSScriptRoot 'Sandbox.ps1')
    $script:Manifest = Get-Content (Join-Path $script:RepoRoot 'shared/tools.json') -Raw | ConvertFrom-Json
    $script:Motd = $script:Manifest.uvTools | Where-Object name -eq 'server-motd'
}
AfterAll { Remove-BootstrapSandboxes }

Describe 'server-motd manifest entry' {
    It 'is pinned to a git commit (not on PyPI) for the server role only' {
        $script:Motd | Should -Not -BeNullOrEmpty
        $script:Motd.source | Should -Match '^git\+https://.+@[0-9a-f]{40}$'
        $script:Motd.roles | Should -Be @('server')
    }
    It 'ships a config.toml.example' {
        Test-Path (Join-Path $script:RepoRoot 'shared/server-motd/config.toml.example') | Should -BeTrue
    }
}

Describe 'bootstrap server: server-motd' {
    It 'installs server-motd via uv tool at the pinned commit' {
        $sb = New-BootstrapSandbox -WithUv
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        Read-Log $sb 'uv.log' | Should -Contain "tool install server-motd @ $($script:Motd.source)"
    }
    It 'does not reinstall on a second run' {
        $sb = New-BootstrapSandbox -WithUv
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        @(Read-Log $sb 'uv.log' | Where-Object { $_ -like 'tool install*' }) | Should -HaveCount 1
    }
    It 'reinstalls when the installed pin differs (same version, older commit)' {
        $sb = New-BootstrapSandbox -WithUv
        Set-Content (Join-Path $sb.Bin 'uvtools.txt') 'server-motd v0.1.0 [required:  git+https://github.com/mookeyj79/Server-MOTD@0000000000000000000000000000000000000000]'
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        Read-Log $sb 'uv.log' | Should -Contain "tool install server-motd @ $($script:Motd.source)"
    }
    It 'installs uv first when absent, then server-motd' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        Read-Log $sb 'irm.log' | Should -HaveCount 1
        Read-Log $sb 'uv.log' | Should -Contain "tool install server-motd @ $($script:Motd.source)"
    }
    It 'skips the dev layer and dev tools' {
        $sb = New-BootstrapSandbox
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        Read-Log $sb 'installed.txt' | Should -Contain 'Starship.Starship'
        Read-Log $sb 'installed.txt' | Should -Not -Contain 'Kubernetes.kubectl'
    }
    It 'devbox installs no server-motd and seeds no motd config' {
        $sb = New-BootstrapSandbox -WithUv
        (Invoke-Bootstrap $sb -Role devbox).ExitCode | Should -Be 0
        Read-Log $sb 'uv.log' | Should -BeNullOrEmpty
        Test-Path $sb.MotdConfig | Should -BeFalse
    }
}

Describe 'bootstrap server: config.toml' {
    It 'seeds config.toml from the example, owner-only' {
        $sb = New-BootstrapSandbox -WithUv
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        $f = Join-Path $sb.MotdConfig 'config.toml'
        Get-Content $f -Raw | Should -Be (Get-Content (Join-Path $sb.Clone 'shared/server-motd/config.toml.example') -Raw)
        if ($IsWindows) {
            $acl = Get-Acl $f
            $acl.AreAccessRulesProtected | Should -BeTrue
            $acl.Access | Should -HaveCount 1
            $acl.Access[0].IdentityReference.Value | Should -Be ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
        } else {
            (& stat -c '%a' $f) | Should -Be '600'
        }
    }
    It 'never overwrites an existing config.toml' {
        $sb = New-BootstrapSandbox -WithUv
        New-Item -ItemType Directory $sb.MotdConfig -Force | Out-Null
        $f = Join-Path $sb.MotdConfig 'config.toml'
        Set-Content $f 'mine = true'
        $before = (Get-Item $f).LastWriteTimeUtc
        (Invoke-Bootstrap $sb -Role server).ExitCode | Should -Be 0
        Get-Content $f -Raw | Should -Match 'mine = true'
        (Get-Item $f).LastWriteTimeUtc | Should -Be $before
    }
}

Describe 'bootstrap server: no winget' {
    It 'warns, skips core tool install, and still finishes the rest including server-motd' {
        $sb = New-BootstrapSandbox -NoWinget
        $r = Invoke-Bootstrap $sb -Role server
        $r.ExitCode | Should -Be 0
        ($r.Output -join "`n") | Should -Match 'winget not found'
        Test-Path $sb.Profile | Should -BeTrue
        Read-Log $sb 'uv.log' | Should -Contain "tool install server-motd @ $($script:Motd.source)"
        Test-Path (Join-Path $sb.MotdConfig 'config.toml') | Should -BeTrue
    }
}

Describe 'profile: server-motd at login' {
    BeforeAll {
        # The sandbox itself is a `pwsh -NonInteractive -Command` session, so to see
        # the interactive path, stub the session check and re-run the MOTD file.
        $motd = Join-Path $script:RepoRoot 'powershell/core/conf.d/60-motd.ps1'
        $script:AsInteractive = "function Test-NowhereInteractiveSession { `$true }; . '$motd'"
    }
    It 'server with server-motd on PATH runs it in an interactive session' {
        $r = Invoke-NowhereSession -Role server -Tools 'server-motd' -Probe $script:AsInteractive
        $r.Errors | Should -BeNullOrEmpty
        ($r.Output -join "`n") | Should -Match 'server-motd'
    }
    It 'server does not run it in a command session (ssh host cmd, Ansible, scripts)' {
        $r = Invoke-NowhereSession -Role server -Tools 'server-motd'
        $r.Errors | Should -BeNullOrEmpty
        ($r.Output -join "`n") | Should -Not -Match 'server-motd'
    }
    It 'server without server-motd prints nothing about it and has no errors' {
        $r = Invoke-NowhereSession -Role server -Tools @()
        $r.Errors | Should -BeNullOrEmpty
        ($r.Output -join "`n") | Should -Not -Match 'server-motd'
    }
    It 'devbox never runs it, even when installed' {
        $r = Invoke-NowhereSession -Role devbox -Tools 'server-motd' -Probe $script:AsInteractive
        ($r.Output -join "`n") | Should -Not -Match 'server-motd'
    }
}

BeforeDiscovery {
    # pwsh command lines (split on spaces) and whether the session is interactive.
    $script:SessionCases = @(
        @{ Line = 'pwsh';                                      Expect = $true  }
        @{ Line = 'pwsh -l';                                   Expect = $true  }
        @{ Line = 'pwsh -NoLogo';                              Expect = $true  }
        @{ Line = 'pwsh -NoExit -Command Set-Location x';      Expect = $true  }
        @{ Line = 'pwsh -c hostname';                          Expect = $false }
        @{ Line = 'pwsh -Command Get-Date';                    Expect = $false }
        @{ Line = 'pwsh -com Get-Date';                        Expect = $false }
        @{ Line = 'pwsh -CommandWithArgs x';                   Expect = $false }
        @{ Line = 'pwsh -cwa x';                               Expect = $false }
        @{ Line = 'pwsh -File s.ps1';                          Expect = $false }
        @{ Line = 'pwsh -f s.ps1 -NoExit';                     Expect = $false }
        @{ Line = 'pwsh -NonInteractive -EncodedCommand AA=='; Expect = $false }
        @{ Line = 'pwsh -ec AA==';                             Expect = $false }
        @{ Line = 'pwsh -noni';                                Expect = $false }
        @{ Line = 'pwsh --command x';                          Expect = $false }
        @{ Line = 'pwsh /Command x';                           Expect = $false }
        @{ Line = 'pwsh -';                                    Expect = $false }
    )
}

# Discovery-time data reaches BeforeAll only through -ForEach.
Describe 'Test-NowhereInteractiveSession' -ForEach @(@{ Cases = $script:SessionCases }) {
    BeforeAll {
        # One sandbox session classifies every case (a session per case is slow).
        $calls = foreach ($c in $Cases) {
            $argv = ($c.Line -split ' ' | ForEach-Object { "'$_'" }) -join ','
            "'$($c.Line)|' + (Test-NowhereInteractiveSession -CommandLine @($argv) -OutputRedirected `$false)"
        }
        $calls += "'redirected|' + (Test-NowhereInteractiveSession -CommandLine @('pwsh') -OutputRedirected `$true)"
        $r = Invoke-NowhereSession -Role server -Tools @() -Probe ($calls -join '; ')
        $script:Results = @{}
        foreach ($l in $r.Output) { if ($l -match '^(.+)\|(True|False)$') { $script:Results[$Matches[1]] = $Matches[2] -eq 'True' } }
    }
    It 'classifies "<Line>" as interactive: <Expect>' -ForEach $script:SessionCases {
        $script:Results.ContainsKey($Line) | Should -BeTrue -Because 'the probe reports every case'
        $script:Results[$Line] | Should -Be $Expect
    }
    It 'treats redirected output as non-interactive' {
        $script:Results['redirected'] | Should -BeFalse
    }
}

Describe 'Update-System on a server' {
    It 'is role-aware and guards winget' {
        $text = Get-Content (Join-Path $script:RepoRoot 'powershell/core/bin/Update-System.ps1') -Raw
        $text | Should -Match 'NowhereRole'
        $text | Should -Match 'Get-Command winget'
    }
}

Describe 'docs' {
    It 'README states install-profile and uninstall-profile are not used' {
        $readme = Get-Content (Join-Path $script:RepoRoot 'README.md') -Raw
        $readme | Should -Match 'install-profile'
        $readme | Should -Match 'uninstall-profile'
    }
}
