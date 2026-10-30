#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Cross-shell parity: consumes tests/parity.txt, the same list the zsh runner
# (tests/zsh/scenarios-parity.sh) consumes. One pwsh session per role+tools group.

BeforeDiscovery {
    $file = Join-Path $PSScriptRoot '../parity.txt'
    $rows = foreach ($l in Get-Content $file) {
        if ($l -match '^\s*(#|$)') { continue }
        $f = $l -split '\|', 7
        if ($f[1] -notin 'both', 'pwsh') { continue }
        @{ Id = $f[0]; Role = $f[2]; Tools = $f[3]; Check = $f[4]; Arg = $f[5]; Expect = $f[6] }
    }
    $groups = @($rows | Group-Object { "$($_.Role)|$($_.Tools)" } | ForEach-Object {
        @{ Role = $_.Group[0].Role; Tools = $_.Group[0].Tools; Rows = @($_.Group) }
    })
}

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

Describe 'parity list (<Role> / <Tools>)' -ForEach $groups {
    BeforeAll {
        $probe = foreach ($r in $Rows) {
            switch ($r.Check) {
                'cmd' { "'P:$($r.Id)=' + `$(if (Get-Command '$($r.Arg)' -EA 0) { 'present' } else { 'absent' })" }
                'env' { "'P:$($r.Id)=' + `$env:$($r.Arg)" }
                'hint' { }
                default { throw "unknown check $($r.Check)" }
            }
        }
        $p = @{ Probe = ((@($probe) + '"done"') -join '; '); Tools = @(if ($Tools -ne '-') { $Tools -split ',' }) }
        if ($Role -ne 'unset') { $p.Role = $Role }
        $session = Invoke-NowhereSession @p
    }
    It 'starts without errors' {
        $session.Errors | Should -BeNullOrEmpty
    }
    It '<Id>: <Check> <Arg> = <Expect>' -ForEach $Rows {
        if ($Check -eq 'hint') {
            @($session.Output | Where-Object { $_ -match 'run bootstrap' }).Count | Should -Be ([int]$Expect)
        } else {
            $line = $session.Output | Where-Object { $_ -like "P:$Id=*" }
            $line | Should -Be "P:$Id=$Expect"
        }
    }
}
