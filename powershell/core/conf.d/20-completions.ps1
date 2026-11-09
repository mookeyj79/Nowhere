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

# --- Tier 1: Carapace (covers git and the long tail of CLIs) ----------------
$_completion = Get-NowhereCachedInit carapace-init carapace @('_carapace')
if ($_completion) { . $_completion }

# --- Tier 2: Native completers (override Carapace for these tools) ----------
#  Get-NowhereCachedInit (00-environment) caches each by binary mtime.
foreach ($_native in @(
        @('kubectl', 'completion', 'powershell'),
        @('helm', 'completion', 'powershell'),
        @('gh', 'completion', '-s', 'powershell'),
        @('docker', 'completion', 'powershell'))) {
    $_completion = Get-NowhereCachedInit "$($_native[0])-completion" $_native[0] $_native[1..($_native.Count - 1)]
    if ($_completion) {
        try { . $_completion } catch { Write-Verbose "Failed to load completion for $($_native[0]): $_" }
    }
}
Remove-Variable _completion, _native -ErrorAction SilentlyContinue

# --- Tier 3: Live callbacks (run in-process on Tab; no startup cost) --------
if (Test-NowhereTool winget) {
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

if (Test-NowhereTool aws) {
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
