# =============================================================================
#  00-environment.ps1
#  Env vars and encoding. Runs first so every later file sees them.
# =============================================================================

# UTF-8 everywhere — fixes Nerd Font icons and accented chars in completions
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# --- Tool presence and the one-per-session bootstrap hint --------------------
#  The profile never installs anything: a missing tool is skipped silently and
#  50-init prints at most one "run bootstrap" hint per session.
function Test-NowhereTool {
    param([Parameter(Mandatory)] [string]$Name)
    [bool](Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
}

# Get-NowhereCachedInit <name> <tool> [args...]: the path of a cached copy of
# `<tool> [args...]` output (an init or completion script), regenerated only
# when the tool's binary is newer than the cache, so a warm start spawns
# nothing. $null when the tool is absent or the generation fails. The caller
# dot-sources the path, so what the script defines lands in the caller's scope.
# zsh's counterpart is _nowhere_cached_init in 50-init.zsh.
function Get-NowhereCachedInit {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Tool,
        [string[]]$Arguments = @()
    )
    $bin = Get-Command $Tool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $bin) { return }
    $file = Join-Path $global:NowhereCacheDir "$Name.ps1"
    $fresh = $false
    if (Test-Path -LiteralPath $file) {
        try {
            $fresh = (Get-Item -LiteralPath $file -ErrorAction Stop).LastWriteTimeUtc -gt
                     (Get-Item -LiteralPath $bin.Source -ErrorAction Stop).LastWriteTimeUtc
        } catch { }
    }
    if (-not $fresh) {
        try {
            $out = & $bin.Source @Arguments 2>$null
            $null = [IO.Directory]::CreateDirectory($global:NowhereCacheDir)
            [IO.File]::WriteAllText($file, ($out -join "`n"), [Text.UTF8Encoding]::new($false))
        } catch {
            Write-Verbose "Failed to generate $Name from ${Tool}: $_"
            return
        }
    }
    $file
}
# Is this an interactive login, not a command session? `ssh host cmd` runs
# `pwsh -c`, Ansible uses -NonInteractive -EncodedCommand, scripts use -File,
# and all of them load the profile, so login banners check this first to stay
# out of the command's output. -NoExit before -Command/-File keeps the session
# interactive. pwsh takes any unambiguous parameter prefix (-com, -noni), so
# names are matched by prefix. [Environment]::UserInteractive is not used: it
# is false under the OpenSSH service, where real logins happen.
function Test-NowhereInteractiveSession {
    param(
        [string[]]$CommandLine = [Environment]::GetCommandLineArgs(),
        [bool]$OutputRedirected = [Console]::IsOutputRedirected
    )
    if ($OutputRedirected) { return $false }
    $noExit = $false
    foreach ($a in @($CommandLine | Select-Object -Skip 1)) {
        if ($a -eq '-') { return $false }                       # command read from stdin
        if ($a -notmatch '^(?:--?|/)([A-Za-z]+)$') { continue }
        $n = $Matches[1].ToLowerInvariant()
        if ($n.Length -ge 3 -and 'noexit'.StartsWith($n)) { $noExit = $true; continue }
        if ($n.Length -ge 4 -and 'noninteractive'.StartsWith($n)) { return $false }
        # -Command/-CommandWithArgs/-File/-EncodedCommand: the rest of the line is
        # the command or its arguments, so stop reading switches here.
        if ($n -in 'cwa', 'ec' -or 'commandwithargs'.StartsWith($n) -or 'file'.StartsWith($n) -or 'encodedcommand'.StartsWith($n)) {
            return $noExit
        }
    }
    $true
}

# The tools whose absence triggers the hint: shared/core-tools.txt, one per line.
$global:NowhereCoreTools = @(Get-Content -LiteralPath (Join-Path $global:NowhereRepoDir 'shared/core-tools.txt') |
    Where-Object { $_ -and $_ -notmatch '^\s*#' })
$global:NowhereHintShown = $false

# Editor: nano by default (dev layer switches to 'code --wait'); local.ps1 can set $NowhereEditor
$env:EDITOR = if ($NowhereEditor) { $NowhereEditor } else { 'nano' }
$env:VISUAL = $env:EDITOR

# Pager
$env:PAGER = 'less'
$env:LESS  = '-R -F -X'   # -R color passthrough, -F quit if one screen, -X no init

# Central virtualenv store — mirrors virtualenvwrapper convention
# uv venvs go here via mkvirtualenv; project-local .venv dirs are separate
$env:WORKON_HOME = Join-Path $HOME '.venvs'

# Local bin — scripts that live alongside the profile, available everywhere
# (core/bin and dev/bin are added to PATH by profile.ps1)

# Cache for generated init scripts and completions
$global:NowhereCacheDir =
    if ($env:LOCALAPPDATA)     { Join-Path $env:LOCALAPPDATA 'pwsh-completion-cache' }
    elseif ($env:XDG_CACHE_HOME) { Join-Path $env:XDG_CACHE_HOME 'pwsh-completion-cache' }
    else                       { Join-Path $HOME '.cache/pwsh-completion-cache' }

# Multi-context kubeconfig — merges every config / *.yaml / *.yml in ~/.kube
$kubeDir = Join-Path $HOME '.kube'
if (Test-Path $kubeDir) {
    $configs  = Get-ChildItem $kubeDir -Filter 'config' -File -ErrorAction SilentlyContinue
    $configs += Get-ChildItem $kubeDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue
    $configs += Get-ChildItem $kubeDir -Filter '*.yml'  -File -ErrorAction SilentlyContinue
    if ($configs) {
        $env:KUBECONFIG = ($configs.FullName -join [IO.Path]::PathSeparator)
    }
}
