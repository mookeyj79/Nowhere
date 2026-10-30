# =============================================================================
#  40-profile.ps1
#  Profile management: reload, edit, update, show aliases.
# =============================================================================

# =============================================================================
#  Profile management
# =============================================================================

function Reload-Profile {
    Write-Host 'Reloading profile...' -ForegroundColor Cyan
    . $PROFILE
}
Set-Alias -Name reload -Value Reload-Profile

function Edit-Profile {
    $e, $editorArgs = -split $env:EDITOR
    & $e @editorArgs $global:NowhereRepoDir
}
Set-Alias -Name editp -Value Edit-Profile

function Update-PSProfile {
    Write-Host 'Updating PowerShell modules (to their pins)...' -ForegroundColor Cyan
    Update-PinnedModules
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host 'Updating winget packages...' -ForegroundColor Cyan
        winget upgrade --all --include-unknown --silent
    }
    Write-Host "Done. Run 'reload' to pick up changes." -ForegroundColor Green
}

function Show-Aliases {
    param([string]$Filter = '*')
    Get-Alias |
        Where-Object { $_.Name -like $Filter } |
        Sort-Object Name |
        Format-Table Name, Definition -AutoSize
}
Set-Alias -Name aliases -Value Show-Aliases

# Update-System is the PowerShell function behind the shared `update` name.
function Update-System {
    & (Join-Path $global:NowhereProfileDir 'core/bin/Update-System.ps1') @args
}
Set-Alias -Name update -Value Update-System

