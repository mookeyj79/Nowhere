#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

Describe 'tool-guarded aliases' {
    It 'core git aliases exist only when git is on PATH' {
        $with = Invoke-NowhereSession -Role server -Tools git -Probe '"gst=" + [bool](Get-Command gst -EA 0)'
        $without = Invoke-NowhereSession -Role server -Tools @() -Probe '"gst=" + [bool](Get-Command gst -EA 0)'
        $with.Output | Should -Contain 'gst=True'
        $without.Output | Should -Contain 'gst=False'
        $without.Errors | Should -BeNullOrEmpty
    }
    It 'eza aliases exist only when eza is on PATH' {
        $p = '"ll=" + [bool](Get-Command ll -EA 0)'
        (Invoke-NowhereSession -Role server -Tools eza -Probe $p).Output | Should -Contain 'll=True'
    }
}

Describe 'dev alias layer' {
    It 'devbox with tofu gets topl; server does not' {
        $p = '"topl=" + [bool](Get-Command topl -EA 0)'
        (Invoke-NowhereSession -Role devbox -Tools tofu -Probe $p).Output | Should -Contain 'topl=True'
        (Invoke-NowhereSession -Role server -Tools tofu -Probe $p).Output | Should -Contain 'topl=False'
    }
    It 'terraform/kubectl/docker aliases are guarded by their tool' {
        $p = '"tfp=" + [bool](Get-Command tfp -EA 0); "kgp=" + [bool](Get-Command kgp -EA 0); "dcup=" + [bool](Get-Command dcup -EA 0)'
        $none = Invoke-NowhereSession -Role devbox -Tools @() -Probe $p
        $none.Output | Should -Contain 'tfp=False'
        $none.Output | Should -Contain 'kgp=False'
        $none.Output | Should -Contain 'dcup=False'
        $none.Errors | Should -BeNullOrEmpty
        $all = Invoke-NowhereSession -Role devbox -Tools terraform, kubectl, docker -Probe $p
        $all.Output | Should -Contain 'tfp=True'
        $all.Output | Should -Contain 'kgp=True'
        $all.Output | Should -Contain 'dcup=True'
    }
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
    It 'Update-Uv runs uv self update when uv exists' {
        $r = Invoke-NowhereSession -Role server -Tools uv -Probe 'Update-Uv'
        $r.Errors | Should -BeNullOrEmpty
        ($r.Output -join ' ') | Should -Match 'uv self update'
    }
    It 'Update-Uv skips quietly when uv is absent' {
        $r = Invoke-NowhereSession -Role server -Tools @() -Probe 'Update-Uv'
        $r.Errors | Should -BeNullOrEmpty
        ($r.Output -join ' ') | Should -Match 'uv not found'
    }
    It 'Update-PinnedModules installs exactly the pinned versions, never floating' {
        $probe = 'function Get-Module { }; function Install-Module { "INSTALL $($args -join '' '')" }; Update-PinnedModules'
        $r = Invoke-NowhereSession -Role server -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $pins = (Get-Content (Join-Path $script:RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json).modules
        foreach ($m in $pins) {
            ($r.Output -join "`n") | Should -Match "INSTALL -Name $($m.name) -RequiredVersion $([regex]::Escape($m.version))"
        }
    }
    It 'Update-PinnedModules leaves modules already at the pin alone' {
        $probe = 'function Get-Module { [pscustomobject]@{ Version = [version](Get-Content (Join-Path $global:NowhereRepoDir ''powershell/modules.json'') -Raw | ConvertFrom-Json).modules[0].version } }; function Install-Module { "INSTALL $($args -join '' '')" }; Update-PinnedModules'
        $r = Invoke-NowhereSession -Role server -Probe $probe
        ($r.Output -join "`n") | Should -Not -Match 'INSTALL -Name PSReadLine'
    }
    It 'Update-PSProfile does not float modules with Update-Module' {
        $text = Get-Content (Join-Path $script:RepoRoot 'powershell/core/conf.d/40-profile.ps1') -Raw
        $text | Should -Not -Match 'Update-Module'
        $text | Should -Match 'Update-PinnedModules'
    }
    It 'Update-System runs uv and pinned-module refresh' {
        $text = Get-Content (Join-Path $script:RepoRoot 'powershell/core/bin/Update-System.ps1') -Raw
        $text | Should -Match 'Update-Uv'
        $text | Should -Match 'Update-PinnedModules'
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

Describe 'missing tools' {
    It 'starts silently apart from one run-bootstrap hint' {
        $r = Invoke-NowhereSession -Role devbox -Tools @() -Probe '"ok"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'ok'
        @($r.Output | Where-Object { $_ -match 'bootstrap' }).Count | Should -Be 1
    }
    It 'prints no hint when nothing is missing' {
        $r = Invoke-NowhereSession -Role server -Tools starship, zoxide, carapace, fzf, eza, git -Probe '"ok"'
        @($r.Output | Where-Object { $_ -match 'bootstrap' }).Count | Should -Be 0
    }
}
