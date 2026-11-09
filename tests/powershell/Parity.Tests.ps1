#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# Cross-shell parity: consumes tests/parity.txt, the same list the zsh runner
# (tests/zsh/scenarios-parity.sh) consumes (format: the header of parity.txt).
# One pwsh session per role+tools+local group.

BeforeDiscovery {
    $file = Join-Path $PSScriptRoot '../parity.txt'
    $rows = foreach ($l in Get-Content $file) {
        if ($l -match '^\s*(#|$)') { continue }
        $f = $l -split '\|', 8
        if ($f[1] -notin 'both', 'pwsh') { continue }
        @{ Id = $f[0]; Role = $f[2]; Tools = $f[3]; Local = $f[4]; Check = $f[5]; Arg = $f[6]; Expect = $f[7] }
    }
    $groups = @($rows | Group-Object { "$($_.Role)|$($_.Tools)|$($_.Local)" } | ForEach-Object {
        @{ Role = $_.Group[0].Role; Tools = $_.Group[0].Tools; Local = $_.Group[0].Local; Rows = @($_.Group) }
    })
}

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

# The scenario index (tests/scenarios.txt and tests/zsh/scenarios-*.txt) names a
# pwsh counterpart per line; every name it gives must exist (format: the header
# of tests/scenarios.txt).
Describe 'scenario index' {
    BeforeAll {
        $script:Index = foreach ($f in @(Join-Path $PSScriptRoot '../scenarios.txt') + @(Get-ChildItem (Join-Path $PSScriptRoot '../zsh') -Filter 'scenarios-*.txt').FullName) {
            $n = 0
            foreach ($l in Get-Content $f) {
                $n++
                if ($l -match '^\s*(#|$)') { continue }
                $c = $l -split '\|'
                [pscustomobject]@{ Id = $c[0]; Shells = $c[1]; Pwsh = $c[2]; Fields = $c.Count; Where = "$(Split-Path $f -Leaf):$n" }
            }
        }
        $script:PsFiles = @(Get-ChildItem (Join-Path $PSScriptRoot '../../powershell') -Recurse -Filter '*.ps1').Name
        # Describe/Context and It names, read from the source: names hold no quote
        # except the doubled '' of a PowerShell string.
        $script:TestNames = @{}
        foreach ($t in Get-ChildItem $PSScriptRoot -Filter '*.Tests.ps1') {
            $text = Get-Content $t.FullName -Raw
            $script:TestNames[$t.BaseName] = @{
                Blocks = @([regex]::Matches($text, "(?m)^\s*(?:Describe|Context) '((?:[^']|'')*)'") | ForEach-Object { $_.Groups[1].Value -replace "''", "'" })
                Its    = @([regex]::Matches($text, "(?m)^\s*It '((?:[^']|'')*)'") | ForEach-Object { $_.Groups[1].Value -replace "''", "'" })
            }
        }
    }
    It 'every line is a record: id|shells|pwsh|asserts' {
        $bad = $script:Index | Where-Object {
            $_.Fields -ne 4 -or $_.Id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$' -or $_.Shells -notin 'both', 'zsh'
        } | ForEach-Object Where
        $bad | Should -BeNullOrEmpty
    }
    It 'lists every id once' {
        $dup = $script:Index | Group-Object Id | Where-Object Count -gt 1 | ForEach-Object Name
        $dup | Should -BeNullOrEmpty
    }
    It 'every line names a real test, a real pwsh file, or n/a' {
        $bad = foreach ($row in $script:Index) {
            $p = $row.Pwsh
            if ($p -match '^(\w+\.Tests): (.+)$') {
                $names = $script:TestNames[$Matches[1]]
                $block, $it = $Matches[2] -split ' / ', 2
                if (-not $names) { "$($row.Id): no $($Matches[1]).ps1"; continue }
                if (-not ($names.Blocks | Where-Object { $_.StartsWith($block) })) { "$($row.Id): no Describe '$block'" }
                if ($it -and -not ($names.Its | Where-Object { $_.StartsWith($it) })) { "$($row.Id): no It '$it'" }
            } elseif ($p -match '^([\w.-]+\.ps1): ') {
                if ($Matches[1] -notin $script:PsFiles) { "$($row.Id): no powershell file $($Matches[1])" }
            } elseif ($p -notmatch '^n/a') {
                "$($row.Id): unrecognised pwsh column '$p'"
            }
        }
        $bad | Should -BeNullOrEmpty
    }
    It 'a line run by both shells names its Pester test' {
        $bad = $script:Index | Where-Object { $_.Shells -eq 'both' -and $_.Pwsh -notmatch '^\w+\.Tests: ' } | ForEach-Object Id
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'parity list (<Role> / <Tools> / <Local>)' -ForEach $groups {
    BeforeAll {
        $probe = foreach ($r in $Rows) {
            switch ($r.Check) {
                'cmd' { "'P:$($r.Id)=' + `$(if (Get-Command '$($r.Arg)' -EA 0) { 'present' } else { 'absent' })" }
                'env' { "'P:$($r.Id)=' + `$env:$($r.Arg)" }
                'hint' { }
                default { throw "unknown check $($r.Check)" }
            }
        }
        $toolList = @(switch ($Tools) { '-' { } 'core' { Get-NowhereCoreToolList } default { $Tools -split ',' } })
        $p = @{ Probe = ((@($probe) + '"done"') -join '; '); Tools = $toolList }
        if ($Role -ne 'unset') { $p.Role = $Role }
        switch ($Local) {
            '-' { }
            'empty' { $p.LocalOverride = '' }
            default {
                $p.LocalOverride = @($Local -split ';' | ForEach-Object {
                    $name, $value = $_ -split '=', 2
                    "`$$name = '$value'"
                }) -join "`n"
            }
        }
        $session = Invoke-NowhereSession @p
    }
    It 'starts cleanly' {
        $session.Errors | Should -BeNullOrEmpty
        $session.ExitCode | Should -Be 0
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
