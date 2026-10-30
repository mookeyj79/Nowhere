# =============================================================================
#  41-goto.ps1
#  Goto bookmarks (extend or override via $NowhereGotoBookmarks in local.ps1)
#  Usage: goto pr   → cd ~/projects
#         goto      → list all bookmarks
# =============================================================================

$script:GotoBookmarks = @{
    pr   = Join-Path $HOME 'projects'
    dot  = Join-Path $HOME '.config'
    pwsh = $global:NowhereProfileDir
    dl   = Join-Path $HOME 'Downloads'
}
if ($NowhereGotoBookmarks) {
    foreach ($_k in $NowhereGotoBookmarks.Keys) { $script:GotoBookmarks[$_k] = $NowhereGotoBookmarks[$_k] }
    Remove-Variable _k
}

function goto {
    param([Parameter(Position = 0)] [string]$Name)
    if (-not $Name) {
        $script:GotoBookmarks.GetEnumerator() |
            Sort-Object Name |
            Format-Table @{n='Bookmark';e={$_.Key}}, @{n='Path';e={$_.Value}}
        return
    }
    $target = $script:GotoBookmarks[$Name]
    if ($target -and (Test-Path $target)) { Set-Location $target }
    else { Write-Warning "Bookmark '$Name' not found. Run 'goto' to list all." }
}

Register-ArgumentCompleter -CommandName goto -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    $script:GotoBookmarks.Keys | Where-Object { $_ -like "$word*" } | Sort-Object
}
