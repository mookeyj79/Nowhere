# =============================================================================
#  35-helpers.ps1
#  Functions with logic (anything that is not a one-liner alias).
# =============================================================================

# --- git clone then cd into the clone ---------------------------------------
function gcl   {
    git clone @args
    if ($LASTEXITCODE -eq 0) {
        Set-Location (($args[-1] -split '/')[-1] -replace '\.git$', '')
    }
}

# --- Files ------------------------------------------------------------------
function touch {
    param($f)
    if (Test-Path $f) { (Get-Item $f).LastWriteTime = Get-Date }
    else { New-Item -ItemType File -Path $f | Out-Null }
}
function mkcd { param($d) New-Item -ItemType Directory -Path $d -Force | Set-Location }

# --- wget -------------------------------------------------------------------
#  wget <url>            → download to current dir, filename derived from URL
#  wget <url> -O file    → download to a specific filename
#  wget <url> -P dir     → download into a specific directory
Remove-Alias wget -Force -ErrorAction SilentlyContinue
function wget {
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Uri,
        [Alias('O')] [string]$OutFile,
        [Alias('P')] [string]$Directory
    )

    # Derive filename from URL if not specified
    if (-not $OutFile) {
        $OutFile = [System.IO.Path]::GetFileName(([uri]$Uri).LocalPath)
        if ([string]::IsNullOrEmpty($OutFile)) { $OutFile = 'index.html' }
    }

    # Prepend directory if given, creating it if needed
    if ($Directory) {
        $null = New-Item -ItemType Directory -Path $Directory -Force -ErrorAction SilentlyContinue
        $OutFile = Join-Path $Directory $OutFile
    }

    Write-Host "-> $OutFile" -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
        $size = (Get-Item $OutFile).Length
        Write-Host "Saved $OutFile ($size bytes)" -ForegroundColor Green
    } catch {
        Write-Error "Download failed: $_"
    }
}

# --- COM Devices ------------------------------------------------------------

if ($IsWindows) {
    function List-COM { Get-PnpDevice -Class Ports -PresentOnly | Select-Object FriendlyName, Status }
}
