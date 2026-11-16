# =============================================================================
#  10-psreadline.ps1
#  History, prediction, key bindings, syntax colors.
#
#  No external modules — colors are inlined as ANSI escape sequences.
# =============================================================================

# --- History ----------------------------------------------------------------
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -MaximumHistoryCount 10000
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally

# --- Prediction (fish-style inline ghost text) ------------------------------
#  InlineView: single grey suggestion after cursor, accepted with End/RightArrow.
#  Keeps UpArrow/DownArrow free for prefix-filtered history search below.
#  Needs a real console; with redirected output (agents, scripts) it errors.
if (-not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle InlineView
}

# --- Editing ----------------------------------------------------------------
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -BellStyle None

# --- Key bindings -----------------------------------------------------------
Set-PSReadLineKeyHandler -Key Tab        -Function MenuComplete          # visual dropdown
Set-PSReadLineKeyHandler -Key Shift+Tab  -Function Complete              # reverse cycle
Set-PSReadLineKeyHandler -Key UpArrow    -Function HistorySearchBackward # prefix-filtered history
Set-PSReadLineKeyHandler -Key DownArrow  -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
Set-PSReadLineKeyHandler -Key Ctrl+f     -Function AcceptSuggestion      # accept full ghost
Set-PSReadLineKeyHandler -Key Alt+f      -Function AcceptNextSuggestionWord # accept one word

# Smart quote insertion — skip over a closing quote the cursor is sitting on
Set-PSReadLineKeyHandler -Key '"', "'" -BriefDescription SmartInsertQuote `
    -ScriptBlock {
        param($key, $arg)
        $line = $null; $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($line.Length -gt $cursor -and $line[$cursor] -eq $key.KeyChar) {
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        } else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$($key.KeyChar)")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
    }

# --- Syntax colors: the terminal's sixteen ------------------------------------
#  SGR codes for the terminal's own palette (30-37 normal, 90-97 bright), so the
#  command line follows the terminal's theme. 39 is the terminal's foreground;
#  7 (reverse video) marks the selection. The tokens zsh also colors take the
#  same color there (tests/syntax-colors.txt). A theme file
#  (~/.config/nowhere/theme.ps1) loads after this one and can change any of them.
Set-PSReadLineOption -Colors @{
    Command            = "`e[34m"   # blue
    Comment            = "`e[90m"   # bright black
    ContinuationPrompt = "`e[36m"   # cyan
    Default            = "`e[39m"   # terminal foreground
    Emphasis           = "`e[31m"   # red
    Error              = "`e[31m"   # red
    InlinePrediction   = "`e[90m"   # bright black
    Keyword            = "`e[35m"   # magenta
    ListPrediction     = "`e[35m"   # magenta
    Member             = "`e[39m"   # terminal foreground
    Number             = "`e[91m"   # bright red
    Operator           = "`e[96m"   # bright cyan
    Parameter          = "`e[95m"   # bright magenta
    Selection          = "`e[7m"    # reverse video
    String             = "`e[32m"   # green
    Type               = "`e[33m"   # yellow
    Variable           = "`e[36m"   # cyan
}
