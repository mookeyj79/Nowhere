#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

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
