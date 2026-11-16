#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }

BeforeAll { . (Join-Path $PSScriptRoot 'Sandbox.ps1') }

# Tool guards, dev-layer role gating and the missing-tools hint are rows of
# tests/parity.txt, run by Parity.Tests.ps1.

Describe 'dev alias layer' {
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
    It 'Update-PSProfile brings modules to their pins and never runs winget' {
        $probe = 'function Get-Module { }; function Install-Module { "INSTALL $($args -join '' '')" }; Update-PSProfile'
        $r = Invoke-NowhereSession -Role devbox -Tools winget -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $pins = (Get-Content (Join-Path $script:RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json).modules
        foreach ($m in $pins) {
            ($r.Output -join "`n") | Should -Match "INSTALL -Name $($m.name) -RequiredVersion $([regex]::Escape($m.version))"
        }
        $r.Output | Where-Object { $_ -match '^winget ' } | Should -BeNullOrEmpty
    }
}

Describe 'shared starship config' {
    BeforeAll { $script:Toml = Get-Content -Raw (Join-Path $script:RepoRoot 'shared/starship.toml') }
    It 'has no palette' {
        $script:Toml | Should -Not -Match '(?m)^\s*palette\s*='
        $script:Toml | Should -Not -Match '(?m)^\s*\[palettes\.'
    }
    It 'uses only the terminal''s sixteen colors, by name' {
        $names = 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white'
        $allowed = $names + ($names | ForEach-Object { "bright-$_" }) +
            'bold', 'italic', 'underline', 'dimmed', 'inverted', 'blink', 'hidden', 'strikethrough', 'reset', 'none'
        # Every style: the (...) after a [text] group, and every style = "..." value.
        $styles = @([regex]::Matches($script:Toml, '\]\(([^)$]*)\)') | ForEach-Object { $_.Groups[1].Value }) +
            @([regex]::Matches($script:Toml, '(?m)^\s*style\w*\s*=\s*["'']([^"'']*)["'']') | ForEach-Object { $_.Groups[1].Value })
        $styles.Count | Should -BeGreaterThan 20
        $bad = foreach ($s in $styles) {
            foreach ($w in $s -split '\s+' | Where-Object { $_ }) {
                if (($w -replace '^(fg|bg):', '') -notin $allowed) { "$w (in '$s')" }
            }
        }
        $bad | Should -BeNullOrEmpty
    }
    It 'is the config PowerShell uses when starship is present' {
        $r = Invoke-NowhereSession -Role server -Tools starship -Probe '"cfg=$env:STARSHIP_CONFIG"'
        ($r.Output -join "`n") | Should -Match 'cfg=.*shared[\\/]starship\.toml'
    }
}

Describe 'cached init' {
    It 'caches the generated script under the cache dir and dot-sources it' {
        $probe = '$f = Join-Path $global:NowhereCacheDir ''starship-init.ps1''; "cached=" + (Get-Content $f -Raw).Trim()'
        $r = Invoke-NowhereSession -Role server -Tools starship -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'cached=starship init powershell'
        # the cached script ran: the shim's echo of its own arguments
        $r.Output | Should -Contain 'starship init powershell'
    }
    It 'regenerates only when the binary is newer than the cache' {
        $probe = @'
$b = (Get-Command starship -CommandType Application).Source
$f = Join-Path $global:NowhereCacheDir 'starship-init.ps1'
Set-Content $f "'warm'"; (Get-Item $b).LastWriteTimeUtc = [datetime]'2000-01-01'
$null = Get-NowhereCachedInit starship-init starship @('init', 'powershell'); "old-bin=" + (Get-Content $f -Raw).Trim()
(Get-Item $b).LastWriteTimeUtc = [datetime]'2099-01-01'
$null = Get-NowhereCachedInit starship-init starship @('init', 'powershell'); "new-bin=" + (Get-Content $f -Raw).Trim()
'@
        $r = Invoke-NowhereSession -Role server -Tools starship -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain "old-bin='warm'"
        $r.Output | Should -Contain 'new-bin=starship init powershell'
    }
    It 'a failing generator caches nothing; empty output is cached' {
        $probe = @'
$d = Join-Path $HOME 'gen'; $null = New-Item -ItemType Directory $d
if ($IsWindows) {
    Set-Content (Join-Path $d 'broken.cmd') '@echo $global:Broken = 1& @exit /b 1'
    Set-Content (Join-Path $d 'quiet.cmd') '@exit /b 0'
} else {
    Set-Content (Join-Path $d 'broken') "#!/bin/sh`necho '`$global:Broken = 1'`nexit 1"
    Set-Content (Join-Path $d 'quiet') "#!/bin/sh`nexit 0"
    foreach ($f in 'broken', 'quiet') { [IO.File]::SetUnixFileMode((Join-Path $d $f), 'UserRead, UserWrite, UserExecute') }
}
$env:PATH = $d + [IO.Path]::PathSeparator + $env:PATH
"broken=[" + (Get-NowhereCachedInit broken-init broken) + "]"
"broken-cached=" + (Test-Path (Join-Path $global:NowhereCacheDir 'broken-init.ps1'))
"quiet-cached=" + [bool](Get-NowhereCachedInit quiet-init quiet)
'@
        $r = Invoke-NowhereSession -Role server -Probe $probe
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'broken=[]'
        $r.Output | Should -Contain 'broken-cached=False'
        $r.Output | Should -Contain 'quiet-cached=True'
    }
    It 'an absent tool gives no script and no error' {
        $r = Invoke-NowhereSession -Role server -Probe '"r=[" + (Get-NowhereCachedInit zoxide-init zoxide @(''init'')) + "]"'
        $r.Errors | Should -BeNullOrEmpty
        $r.Output | Should -Contain 'r=[]'
    }
}

Describe 'missing tools' {
    It 'every core tool in shared/core-tools.txt is a core tool in the manifest' {
        $core = ((Get-Content (Join-Path $script:RepoRoot 'shared/tools.json') -Raw | ConvertFrom-Json).tools |
            Where-Object layer -eq 'core').name
        foreach ($t in Get-NowhereCoreToolList) { $core | Should -Contain $t }
    }
}

# Nowhere names no theme and holds no color values: every color is one of the
# terminal's sixteen, and a theme file (outside the repo) refines them.
Describe 'theme agnostic' {
    It 'names no theme and holds no color value under shared, zsh and powershell' {
        $pattern = 'catppuccin|macchiato|#[0-9a-f]{6}\b|[34]8;[25];'
        $bad = Get-ChildItem -Recurse -File -Path (@('shared', 'zsh', 'powershell') | ForEach-Object { Join-Path $script:RepoRoot $_ }) |
            Select-String -Pattern $pattern |
            ForEach-Object { "$($_.Path.Substring($script:RepoRoot.Length + 1)):$($_.LineNumber): $($_.Line.Trim())" }
        $bad | Should -BeNullOrEmpty
    }
    It 'pins exactly the three zsh plugins, syntax highlighting last' {
        $pins = (Get-Content -Raw (Join-Path $script:RepoRoot 'zsh/plugins.json') | ConvertFrom-Json).plugins.name
        $pins | Should -Be @('zsh-autosuggestions', 'zsh-history-substring-search', 'zsh-syntax-highlighting')
    }
}

# tests/syntax-colors.txt (shared with tests/zsh/scenarios-line-editor.sh):
# every PSReadLine key it names holds its color's SGR code.
Describe 'syntax colors' {
    BeforeDiscovery {
        $rows = foreach ($l in Get-Content (Join-Path $PSScriptRoot '../syntax-colors.txt')) {
            if ($l -match '^\s*(#|$)') { continue }
            $f = $l -split '\|'
            @{ Token = $f[0]; Color = $f[1]; Key = $f[2] }
        }
    }
    BeforeAll {
        $probe = '$o = Get-PSReadLineOption; $o | Get-Member -MemberType Property | Where-Object Name -like ''*Color'' | ForEach-Object { "C:$($_.Name)=" + ($o.($_.Name) -replace "`e", ''ESC'') }'
        $script:Session = Invoke-NowhereSession -Role devbox -Probe $probe
    }
    It 'starts cleanly' { $script:Session.Errors | Should -BeNullOrEmpty }
    It '<Token>: <Key> is <Color>' -ForEach $rows {
        $names = 'black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white'
        $base = $Color -replace '^bright-', ''
        $names | Should -Contain $base
        $code = [array]::IndexOf($names, $base) + $(if ($Color -like 'bright-*') { 90 } else { 30 })
        $script:Session.Output | Should -Contain "C:$($Key)Color=ESC[$($code)m"
    }
}
