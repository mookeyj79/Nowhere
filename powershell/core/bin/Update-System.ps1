#Requires -RunAsAdministrator
param(
    [switch]$Windows,
    [switch]$Winget,
    [switch]$WSL,
    [switch]$DiskCleanup
)

$All = -not ($Windows -or $Winget -or $WSL -or $DiskCleanup)

# On a server (role set by the Nowhere profile) a bare `update` means Windows
# Update plus winget when it exists. WSL is not a server feature and cleanmgr
# is absent without Desktop Experience; both stay available as explicit flags.
if ($All -and $global:NowhereRole -eq 'server') {
    $All = $false
    $Windows = $true
    $Winget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

# Self-updating apps winget should never touch. Pinned automatically if installed.
# Override without editing: set WINGET_PIN_IDS to a comma-separated list of winget IDs.
$PinIds = if ($env:WINGET_PIN_IDS) { $env:WINGET_PIN_IDS -split '[,;\s]+' | Where-Object { $_ } } else {
    'Valve.Steam', 'EpicGames.EpicGamesLauncher', 'Blizzard.BattleNet', 'Ubisoft.Connect',
    'GOG.Galaxy', 'Discord.Discord', 'SlackTechnologies.Slack'
}

# Upgrades one winget source package by package, printing each app as it is processed:
#   [*] AppName
#       [!] Error - <reason>        (only when that app fails)
# winget has no JSON output for `upgrade`, so the candidate table is parsed by column
# position (names and IDs can contain spaces). Output is captured per app so a failure
# is reported right under its own app instead of at the end.
function Update-WingetSource {
    param([Parameter(Mandatory)][string]$Source)

    # winget redraws its spinner with carriage returns; keep only the final redraw.
    $clean = { param($t) ($t -split "`r")[-1].Trim() }

    $raw = winget upgrade --source $Source --include-unknown --accept-source-agreements --disable-interactivity 2>$null |
        ForEach-Object { & $clean "$_" }
    $hdr = $raw | Where-Object { $_ -match '^Name\s+Id\s+Version\s+Available' } | Select-Object -First 1
    if (-not $hdr) { return }

    $idCol  = $hdr.IndexOf('Id')
    $verCol = $hdr.IndexOf('Version')
    $avlCol = $hdr.IndexOf('Available')
    $slice  = {
        param($l, $from, $to)
        if ($l.Length -le $from) { return '' }
        $l.Substring($from, [Math]::Min($to, $l.Length) - $from).Trim()
    }

    $inTable = $false
    foreach ($line in $raw) {
        if ($line -eq $hdr) { $inTable = $true; continue }
        if (-not $inTable -or $line -match '^-+$' -or -not $line) { continue }
        if ($line -match '^\d+ upgrades? available' -or $line -match 'have pins that prevent upgrade') { break }

        $name = & $slice $line 0 $idCol
        $id   = & $slice $line $idCol $verCol
        Write-Host -ForegroundColor Green -NoNewline "[*]"
        Write-Host " $name"

        $out = winget upgrade --id $id --source $Source --include-unknown `
            --accept-source-agreements --accept-package-agreements --silent --disable-interactivity 2>&1 |
            ForEach-Object { & $clean "$_" } | Where-Object { $_ }
        $code = $LASTEXITCODE

        # -1978335189 = "no applicable upgrade": the --include-unknown version mismatch
        # noise (e.g. Ubisoft Connect). Not a failure.
        if ($code -eq 0 -or $code -eq -1978335189) { continue }

        # The reason starts at the first error-looking line; take it plus up to two
        # following lines and fold them into one (e.g. "An unexpected error occurred...
        # Download request status is not success. 0x80190193 : Forbidden (403).").
        [string[]]$lines = $out
        $first = [array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match 'fail|error|forbidden|0x[0-9a-f]{8}' })
        $reason = if ($first -ge 0) {
            $lines[$first..([Math]::Min($first + 2, $lines.Count - 1))] -join ' '
        } else { "exit code $code" }

        Write-Host -ForegroundColor Red -NoNewline "    [!]"
        Write-Host " Error - $reason"
    }
}

if ($Windows -or $All) {
    Write-Host -ForegroundColor Green -NoNewline "[*]"
    Write-Host " Updating Windows..."
    if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module PSWindowsUpdate -Force -Confirm:$false | Out-Null
    }
    Import-Module PSWindowsUpdate
    Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -Confirm:$false | Out-Null

    $results  = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Confirm:$false
    $results += Install-WindowsUpdate -MicrosoftUpdate -UpdateType Driver -AcceptAll -IgnoreReboot -Confirm:$false
    $results | Select-Object Title, Result | Format-Table -AutoSize
    Write-Host -NoNewline "`n"
}

if ($Winget -or $All) {
    Write-Host -ForegroundColor Green -NoNewline "[*]"
    Write-Host " Updating Applications..."

    # Pin first so pinned apps drop out of the upgrade list. Silent unless something
    # gets pinned or a pin fails.
    $pinned = winget pin list --accept-source-agreements 2>$null | Out-String
    foreach ($id in $PinIds) {
        if ($pinned -match [regex]::Escape($id)) { continue }
        winget list --id $id --exact --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }   # not installed
        winget pin add --id $id --exact --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "  Pinned $id" } else { Write-Warning "Could not pin $id" }
    }

    # Preview table: what is about to be updated. The [*] lines below are what is
    # being worked on right now.
    winget upgrade
    Write-Host ""

    Update-WingetSource -Source winget

    if ((winget source list) -match 'msstore') {
        Update-WingetSource -Source msstore

        # winget's msstore source still misses some apps (WhatsApp, To Do, etc).
        # This nudges the Store's own update agent to scan for those.
        $scan = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' `
            -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' |
            Invoke-CimMethod -MethodName UpdateScanMethod
        if ($scan.ReturnValue -ne 0) { Write-Warning "Store update scan returned $($scan.ReturnValue)" }
    }
    else {
        Write-Warning "msstore source unavailable - open Microsoft Store once, then re-run"
    }
    Write-Host -NoNewline "`n"
}

if ($WSL -or $All) {
    Write-Host -ForegroundColor Green -NoNewline "[*]"
    Write-Host " Updating WSL..."
    wsl --update
    wsl.exe --user root -- bash -lc "apt update && apt upgrade -y"
    Write-Host -NoNewline "`n"
}

if ($DiskCleanup -or $All) {
    Write-Host -ForegroundColor Green -NoNewline "[*]"
    Write-Host " Cleaning Disk..."
    $sageId    = 99
    $sageName  = ('StateFlags{0:0000}' -f $sageId)
    $volCaches = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    # Excludes Downloads, Previous Installations (windows.old), ESD install files,
    # and Recycle Bin - those delete things you probably want kept.
    $categories = @(
        'Active Setup Temp Folders','BranchCache','D3D Shader Cache','Delivery Optimization Files',
        'Diagnostic Data Viewer database files','Downloaded Program Files','Internet Cache Files',
        'Memory Dump Files','Offline Pages Files','Old ChkDsk Files','RetailDemo Offline Content',
        'Setup Log Files','System error memory dump files','System error minidump files',
        'Temporary Files','Temporary Setup Files','Temporary Sync Files','Thumbnail Cache',
        'Update Cleanup','Upgrade Discarded Files','User file versions','Windows Defender',
        'Windows Error Reporting Archive Files','Windows Error Reporting Queue Files',
        'Windows Error Reporting System Archive Files','Windows Error Reporting System Queue Files',
        'Windows Upgrade Log Files'
    )
    foreach ($cat in $categories) {
        $key = Join-Path $volCaches $cat
        if (Test-Path -LiteralPath $key) {
            New-ItemProperty -LiteralPath $key -Name $sageName -PropertyType DWord -Value 2 -Force | Out-Null
        }
    }
    Start-Process cleanmgr.exe -ArgumentList "/sagerun:$sageId" -Wait -WindowStyle Hidden
}
