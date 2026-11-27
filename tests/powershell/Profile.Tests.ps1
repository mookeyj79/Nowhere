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

Describe 'theme file' {
    BeforeAll { $script:Core = Get-NowhereCoreToolList }
    It 'is sourced when present' {
        $r = Invoke-NowhereSession -Role devbox -Tools $script:Core -ThemeFile '"theme ran"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'theme ran'
    }
    It 'loads after conf.d, so a color it sets wins' {
        $theme = 'Set-PSReadLineOption -Colors @{ Comment = "`e[33m" }'
        $probe = '$o = Get-PSReadLineOption; "comment=" + ($o.CommentColor -replace "`e", "ESC"); "string=" + ($o.StringColor -replace "`e", "ESC")'
        $r = Invoke-NowhereSession -Role devbox -ThemeFile $theme -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'comment=ESC[33m'
        $r.Output | Should -Contain 'string=ESC[32m'   # untouched: still the conf.d color
    }
    It 'is optional: a missing file prints nothing' {
        $none  = Invoke-NowhereSession -Role devbox -Tools $script:Core
        $empty = Invoke-NowhereSession -Role devbox -Tools $script:Core -ThemeFile ''
        $none.Errors | Should -BeNullOrEmpty
        $none.ExitCode | Should -Be 0
        $none.Output | Should -Be $empty.Output
    }
}
