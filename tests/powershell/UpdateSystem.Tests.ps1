#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }
# The decisions inside Update-System (powershell/core/lib/UpdateSystem.ps1),
# tested without admin rights, a real winget or a real machine.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    . (Join-Path $script:RepoRoot 'powershell/core/lib/UpdateSystem.ps1')

    # A `winget upgrade` table as winget prints it: spinner redraws joined by
    # carriage returns, columns cut at the header's positions, names with spaces.
    $row = { param($n, $i, $v, $a) '{0,-30}{1,-30}{2,-13}{3,-13}{4}' -f $n, $i, $v, $a, 'winget' }
    $script:Table = @(
        "   - `r   \ `r" + (& $row 'Name' 'Id' 'Version' 'Available')
        ('-' * 92)
        (& $row 'Git' 'Git.Git' '2.44.0' '2.45.1')
        (& $row 'Microsoft Visual Studio Code' 'Microsoft.VisualStudioCode' '1.88.0' '1.89.0')
        '2 upgrades available.'
        ''
        (& $row 'Pinned Thing' 'Pinned.Thing' '1.0' '2.0')
    )
}

Describe 'Resolve-UpdateSteps' {
    It 'a bare update on a devbox runs every step, in order' {
        Resolve-UpdateSteps -Role devbox | Should -Be @('Windows', 'Winget', 'Tools', 'WSL', 'DiskCleanup')
    }
    It 'a bare update on a server runs Windows Update, winget and Tools' {
        Resolve-UpdateSteps -Role server -HaveWinget $true | Should -Be @('Windows', 'Winget', 'Tools')
    }
    It 'a server without winget skips the winget step' {
        Resolve-UpdateSteps -Role server -HaveWinget $false | Should -Be @('Windows', 'Tools')
    }
    It 'explicit switches pick exactly those steps on any role' {
        Resolve-UpdateSteps -Role server -Requested 'WSL' | Should -Be @('WSL')
        Resolve-UpdateSteps -Role devbox -Requested 'Tools', 'Windows' | Should -Be @('Windows', 'Tools')
    }
}

Describe 'ConvertFrom-WingetUpgradeTable' {
    It 'reads name and id by column, names with spaces included' {
        $pkgs = @(ConvertFrom-WingetUpgradeTable -Lines $script:Table)
        $pkgs.Count | Should -Be 2
        $pkgs[0].Name | Should -Be 'Git'
        $pkgs[0].Id | Should -Be 'Git.Git'
        $pkgs[1].Name | Should -Be 'Microsoft Visual Studio Code'
        $pkgs[1].Id | Should -Be 'Microsoft.VisualStudioCode'
    }
    It 'stops at the summary line, before pinned packages' {
        (ConvertFrom-WingetUpgradeTable -Lines $script:Table).Id | Should -Not -Contain 'Pinned.Thing'
    }
    It 'returns nothing when there is no table' {
        @(ConvertFrom-WingetUpgradeTable -Lines @('No installed package found matching input criteria.')).Count | Should -Be 0
        @(ConvertFrom-WingetUpgradeTable -Lines @()).Count | Should -Be 0
    }
}

Describe 'Get-WingetFailureReason' {
    It 'success and "no applicable upgrade" are not failures' {
        Get-WingetFailureReason -Lines @('Successfully installed') -ExitCode 0 | Should -BeNullOrEmpty
        Get-WingetFailureReason -Lines @('No applicable upgrade found.') -ExitCode -1978335189 | Should -BeNullOrEmpty
    }
    It 'folds the first error line and up to two after it into one reason' {
        $out = @(
            'Downloading https://example/app.msi'
            "  ██████  `r  ██████████"
            'An unexpected error occurred while executing the command:'
            'Download request status is not success.'
            '0x80190193 : Forbidden (403).'
            'trailing line'
        )
        Get-WingetFailureReason -Lines $out -ExitCode 1 |
            Should -Be 'An unexpected error occurred while executing the command: Download request status is not success. 0x80190193 : Forbidden (403).'
    }
    It 'falls back to the exit code when nothing looks like an error' {
        Get-WingetFailureReason -Lines @('something odd') -ExitCode 5 | Should -Be 'exit code 5'
    }
}

Describe 'Invoke-NowhereToolsUpdate' {
    BeforeEach {
        $script:Fx = Join-Path ([IO.Path]::GetTempPath()) ('nowhere-tools-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:Fx 'shared'), (Join-Path $script:Fx 'powershell'), (Join-Path $script:Fx 'bootstrap') -Force | Out-Null
        Copy-Item (Join-Path $script:RepoRoot 'bootstrap/lib') (Join-Path $script:Fx 'bootstrap/lib') -Recurse
        Copy-Item (Join-Path $script:RepoRoot 'shared/tools.json') (Join-Path $script:Fx 'shared/tools.json')
        Set-Content (Join-Path $script:Fx 'powershell/modules.json') '{"modules":[]}'
        $script:UvDir = Join-Path $script:Fx 'uvbin'
        New-Item -ItemType Directory -Path $script:UvDir | Out-Null
        if ($IsWindows) { Set-Content (Join-Path $script:UvDir 'uv.cmd') "@echo %*>> `"%~dp0uv.log`"" }
        else {
            Set-Content (Join-Path $script:UvDir 'uv') "#!/bin/sh`necho `"`$*`" >> `"`$(dirname `"`$0`")/uv.log`""
            chmod +x (Join-Path $script:UvDir 'uv')
        }
        $script:SavedPath = $env:PATH
        $env:PATH = $script:UvDir + [IO.Path]::PathSeparator + $env:PATH
    }
    AfterEach {
        $env:PATH = $script:SavedPath
        Remove-Item $script:Fx -Recurse -Force -ErrorAction SilentlyContinue
    }
    It 'runs uv self update, then brings the role''s uv tools to their pins' {
        Invoke-NowhereToolsUpdate -Role server -RepoRoot $script:Fx 6> $null
        $log = (Get-Content (Join-Path $script:UvDir 'uv.log')) -join "`n"
        $log | Should -Match 'self update'
        $src = ((Get-Content (Join-Path $script:RepoRoot 'shared/tools.json') -Raw | ConvertFrom-Json).uvTools | Where-Object name -eq 'server-motd').source
        $log | Should -Match ('tool install "?server-motd @ ' + [regex]::Escape($src))
    }
    It 'a devbox gets no server-only uv tools' {
        Invoke-NowhereToolsUpdate -Role devbox -RepoRoot $script:Fx 6> $null
        (Get-Content (Join-Path $script:UvDir 'uv.log')) -join "`n" | Should -Not -Match 'server-motd'
    }
}
