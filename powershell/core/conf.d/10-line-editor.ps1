# =============================================================================
#  10-psreadline.ps1
#  History, prediction, key bindings, Catppuccin Macchiato syntax colors.
#
#  No external modules — colors are inlined as ANSI escape sequences.
#  Dropping the Catppuccin module saves one of the biggest startup costs.
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

# --- Catppuccin Macchiato syntax colors (hardcoded ANSI — no module) --------
Set-PSReadLineOption -Colors @{
    Command            = "`e[38;2;138;173;244m"   # Blue
    Comment            = "`e[38;2;110;115;141m"   # Overlay0
    ContinuationPrompt = "`e[38;2;139;213;202m"   # Teal
    Default            = "`e[38;2;202;211;245m"   # Text
    Emphasis           = "`e[38;2;237;135;150m"   # Red
    Error              = "`e[38;2;237;135;150m"   # Red
    InlinePrediction   = "`e[38;2;128;135;162m"   # Overlay1
    Keyword            = "`e[38;2;198;160;246m"   # Mauve
    ListPrediction     = "`e[38;2;198;160;246m"   # Mauve
    Member             = "`e[38;2;244;219;214m"   # Rosewater
    Number             = "`e[38;2;245;169;127m"   # Peach
    Operator           = "`e[38;2;145;215;227m"   # Sky
    Parameter          = "`e[38;2;245;189;230m"   # Pink
    Selection          = "`e[48;2;54;58;79m"       # Surface0 (background)
    String             = "`e[38;2;166;218;149m"   # Green
    Type               = "`e[38;2;238;212;159m"   # Yellow
    Variable           = "`e[38;2;183;189;248m"   # Lavender
}
