#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

# Role gating and the shared local-override checks (defaults, values win, an
# empty file) are rows of tests/parity.txt, run by Parity.Tests.ps1.

Describe 'local override' {
    It 'is sourced before conf.d, so conf.d reads its values' {
        $local = '$NowhereAnsibleWslDistro = "ubuntu"; $NowhereGotoBookmarks = @{ lab = "/lab" }'
        $r = Invoke-NowhereSession -Role devbox -LocalOverride $local -Probe '"distro=$script:AnsibleWslDistro"; "marks=" + ((goto | Out-String) -match "lab")'
        $r.Output | Should -Contain 'distro=ubuntu'
        $r.Output | Should -Contain 'marks=True'
    }
}
