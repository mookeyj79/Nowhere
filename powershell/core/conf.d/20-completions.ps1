# =============================================================================
#  20-completions.ps1
#  Tab completions via three tiers:
#
#  1. Carapace     — covers ~1000 CLIs (including git); cached by binary mtime
#  2. Native tools — kubectl, helm, gh, docker generate their own completers;
#                    these take precedence over Carapace and are also cached
#  3. Live callbacks — winget and aws run in-process on Tab, not at startup
#
#  On a warm cache each cached tool costs one stat() call at startup.
#  Cache lives in $NowhereCacheDir (%LOCALAPPDATA%\pwsh-completion-cache\ on Windows) and auto-invalidates
#  when a binary is updated.
# =============================================================================

$script:CompletionCacheDir = $global:NowhereCacheDir
$null = [System.IO.Directory]::CreateDirectory($script:CompletionCacheDir)

# --- Generic cached completer helper ----------------------------------------
function Register-CachedCompletion {
    param(
        [Parameter(Mandatory)] [string]   $Command,
        [Parameter(Mandatory)] [string[]] $CompletionArgs
    )
    $bin = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $bin) { return }

    $cacheFile  = Join-Path $script:CompletionCacheDir "$Command-completion.ps1"
    $needsRegen = $true

    if (Test-Path $cacheFile) {
        try {
            $binTime   = (Get-Item -LiteralPath $bin.Source -ErrorAction Stop).LastWriteTimeUtc
            $cacheTime = (Get-Item -LiteralPath $cacheFile  -ErrorAction Stop).LastWriteTimeUtc
            if ($cacheTime -gt $binTime) { $needsRegen = $false }
        } catch { }
    }

    if ($needsRegen) {
        try {
            $output = & $Command @CompletionArgs 2>$null
            [System.IO.File]::WriteAllText(
                $cacheFile,
                ($output -join "`n"),
                [System.Text.Encoding]::UTF8
            )
        } catch {
            Write-Verbose "Failed to generate completion for ${Command}: $_"
            return
        }
    }

    try { . $cacheFile }
    catch { Write-Verbose "Failed to load completion for ${Command}: $_" }
}

# --- Tier 1: Carapace (covers git and the long tail of CLIs) ----------------
$_carapace = Get-Command carapace -ErrorAction SilentlyContinue
if ($_carapace) {
    $cacheFile  = Join-Path $script:CompletionCacheDir 'carapace-init.ps1'
    $needsRegen = $true
    if (Test-Path $cacheFile) {
        try {
            $binTime   = (Get-Item -LiteralPath $_carapace.Source -ErrorAction Stop).LastWriteTimeUtc
            $cacheTime = (Get-Item -LiteralPath $cacheFile        -ErrorAction Stop).LastWriteTimeUtc
            if ($cacheTime -gt $binTime) { $needsRegen = $false }
        } catch { }
    }
    if ($needsRegen) {
        carapace _carapace | Set-Content -Path $cacheFile -Encoding UTF8
    }
    . $cacheFile
}
Remove-Variable _carapace

# --- Tier 2: Native completers (override Carapace for these tools) ----------
Register-CachedCompletion 'kubectl' @('completion', 'powershell')
Register-CachedCompletion 'helm'    @('completion', 'powershell')
Register-CachedCompletion 'gh'      @('completion', '-s', 'powershell')
Register-CachedCompletion 'docker'  @('completion', 'powershell')

# --- Tier 3: Live callbacks (run in-process on Tab; no startup cost) --------
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding =
            $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $word = $wordToComplete.Replace('"', '""')
        $ast  = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$word" --commandline "$ast" --position $cursorPosition |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }
}

if (Get-Command aws -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName aws -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $env:COMP_LINE  = $commandAst.ToString()
        $env:COMP_POINT = $cursorPosition
        aws_completer.exe 2>$null | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
        Remove-Item Env:\COMP_LINE, Env:\COMP_POINT -ErrorAction SilentlyContinue
    }
}
