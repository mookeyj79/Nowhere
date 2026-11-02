#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

Describe 'role gating' {
    It 'devbox gets core and dev layers' {
        $r = Invoke-NowhereSession -Role devbox -Probe '"core=" + [bool](Get-Command gst -EA 0); "dev=" + [bool](Get-Command ansible-playbook -EA 0); "editor=$env:EDITOR"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'core=True'
        $r.Output | Should -Contain 'dev=True'
        $r.Output | Should -Contain 'editor=code --wait'
    }
    It 'server gets core only' {
        $r = Invoke-NowhereSession -Role server -Probe '"core=" + [bool](Get-Command gst -EA 0); "dev=" + [bool](Get-Command ansible-playbook -EA 0); "editor=$env:EDITOR"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'core=True'
        $r.Output | Should -Contain 'dev=False'
        $r.Output | Should -Contain 'editor=nano'
    }
    It 'an unset role behaves like server' {
        $r = Invoke-NowhereSession -Probe '"dev=" + [bool](Get-Command ansible-playbook -EA 0)'
        $r.Output | Should -Contain 'dev=False'
    }
}

Describe 'local override' {
    It 'starts cleanly with defaults when no override exists' {
        $r = Invoke-NowhereSession -Role devbox -Probe '"goto=" + [bool](Get-Command goto -EA 0)'
        $r.Errors | Should -BeNullOrEmpty
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Contain 'goto=True'
    }
    It 'override values win over defaults' {
        $local = '$NowhereEditor = "vim"'
        $r = Invoke-NowhereSession -Role devbox -LocalOverride $local -Probe '"editor=$env:EDITOR"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'editor=vim'
    }
    It 'is sourced before conf.d, so conf.d reads its values' {
        $local = '$NowhereAnsibleWslDistro = "ubuntu"; $NowhereGotoBookmarks = @{ lab = "/lab" }'
        $r = Invoke-NowhereSession -Role devbox -LocalOverride $local -Probe '"distro=$script:AnsibleWslDistro"; "marks=" + ((goto | Out-String) -match "lab")'
        $r.Output | Should -Contain 'distro=ubuntu'
        $r.Output | Should -Contain 'marks=True'
    }
    It 'tolerates an empty override' {
        $r = Invoke-NowhereSession -Role server -LocalOverride '' -Probe '"editor=$env:EDITOR"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'editor=nano'
    }
}
