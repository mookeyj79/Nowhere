# =============================================================================
#  42-venv.ps1
#  Virtualenv helpers — uv-backed, virtualenvwrapper-style
#  Named envs live in $env:WORKON_HOME (~\.venvs\)
#  Project-local envs (uv venv) go in .venv and use the activate function below
# =============================================================================

function mkvirtualenv {
    param([string]$Name, [string]$Python)
    if (-not $Name) { Write-Error 'Usage: mkvirtualenv <name> [-Python 3.x]'; return }
    $target = Join-Path $env:WORKON_HOME $Name
    $pyArg  = if ($Python) { @('--python', $Python) } else { @() }
    uv venv $target @pyArg
    if ($LASTEXITCODE -eq 0) { . (Join-Path $target 'Scripts\Activate.ps1') }
}

function workon {
    if (-not $args[0]) { lsvirtualenv; return }
    $activator = Join-Path $env:WORKON_HOME "$($args[0])\Scripts\Activate.ps1"
    if (Test-Path $activator) { . $activator }
    else { Write-Error "virtualenv '$($args[0])' not found. Run 'workon' to list." }
}

function rmvirtualenv {
    if (-not $args[0]) { Write-Error 'Usage: rmvirtualenv <name>'; return }
    $target = Join-Path $env:WORKON_HOME $args[0]
    if ($env:VIRTUAL_ENV -eq $target) { deactivate }
    if (Test-Path $target) {
        Remove-Item $target -Recurse -Force
        Write-Host "Removed virtualenv '$($args[0])'." -ForegroundColor Yellow
    } else { Write-Error "virtualenv '$($args[0])' not found." }
}

function lsvirtualenv {
    Write-Host 'Available virtualenvs:' -ForegroundColor Cyan
    if (Test-Path $env:WORKON_HOME) {
        Get-ChildItem $env:WORKON_HOME -Directory | Select-Object -ExpandProperty Name
    } else { Write-Host '  (none)' -ForegroundColor DarkGray }
}

function cdvirtualenv {
    if ($env:VIRTUAL_ENV) { Set-Location $env:VIRTUAL_ENV }
    else { Write-Error 'No virtualenv is currently active.' }
}

Register-ArgumentCompleter -CommandName workon    -ParameterName args -ScriptBlock {
    param($cmd, $param, $word)
    if (Test-Path $env:WORKON_HOME) {
        Get-ChildItem $env:WORKON_HOME -Directory |
            Where-Object { $_.Name -like "$word*" } |
            Select-Object -ExpandProperty Name
    }
}
Register-ArgumentCompleter -CommandName rmvirtualenv -ParameterName args -ScriptBlock {
    param($cmd, $param, $word)
    if (Test-Path $env:WORKON_HOME) {
        Get-ChildItem $env:WORKON_HOME -Directory |
            Where-Object { $_.Name -like "$word*" } |
            Select-Object -ExpandProperty Name
    }
}

# Seed pip into a named or active virtualenv
# uv venvs don't include pip by default — run this once after mkvirtualenv
# Usage: seedvenv           → seeds active env
#        seedvenv myenv     → seeds named env without activating it
function seedvenv {
    param([Parameter(Position = 0)] [string]$Env)

    if ($Env) {
        $venvPath = Join-Path $env:WORKON_HOME $Env
        if (-not (Test-Path (Join-Path $venvPath 'Scripts'))) {
            Write-Error "virtualenv '$Env' not found. Run 'lsvirtualenv' to list available."
            return
        }
        Write-Host "  -> Seeding pip into '$Env'" -ForegroundColor Cyan
        uv pip install pip --python $venvPath
    } elseif ($env:VIRTUAL_ENV) {
        Write-Host "  -> Seeding pip into '$(Split-Path $env:VIRTUAL_ENV -Leaf)'" -ForegroundColor Cyan
        uv pip install pip
    } else {
        Write-Error "No virtualenv active and no name specified. Run 'workon <env>' first or pass a name."
    }
}

Register-ArgumentCompleter -CommandName seedvenv -ParameterName Env -ScriptBlock {
    param($cmd, $param, $word)
    if (Test-Path $env:WORKON_HOME) {
        Get-ChildItem $env:WORKON_HOME -Directory |
            Where-Object { $_.Name -like "$word*" } |
            Select-Object -ExpandProperty Name
    }
}

# Install packages into a named or active virtualenv
function pipinstall {
    param(
        [Alias('e')] [string]$Env,
        [Parameter(ValueFromRemainingArguments)] [string[]]$Packages
    )
    if (-not $Packages) { Write-Error 'Usage: pipinstall [-Env <name>] <package> [package...]'; return }

    if ($Env) {
        $venvPath = Join-Path $env:WORKON_HOME $Env
        if (-not (Test-Path (Join-Path $venvPath 'Scripts'))) {
            Write-Error "virtualenv '$Env' not found. Run 'lsvirtualenv' to list available."
            return
        }
        Write-Host "  -> $Env" -ForegroundColor Cyan
        uv pip install --python $venvPath @Packages
    } elseif ($env:VIRTUAL_ENV) {
        Write-Host "  -> $(Split-Path $env:VIRTUAL_ENV -Leaf)" -ForegroundColor Cyan
        uv pip install @Packages
    } else {
        Write-Error "No virtualenv active and no -Env specified. Run 'workon <env>' first or use -Env <name>."
    }
}

Register-ArgumentCompleter -CommandName pipinstall -ParameterName Env -ScriptBlock {
    param($cmd, $param, $word)
    if (Test-Path $env:WORKON_HOME) {
        Get-ChildItem $env:WORKON_HOME -Directory |
            Where-Object { $_.Name -like "$word*" } |
            Select-Object -ExpandProperty Name
    }
}

# =============================================================================
#  activate — for project-local .venv dirs (created with `uv venv`)
#  Usage: activate        → list venvs in current directory
#         activate myenv  → activate it
# =============================================================================

function activate {
    param([Parameter(Position = 0)] [string]$Name)
    if (-not $Name) {
        Get-ChildItem -Directory | Where-Object {
            Test-Path (Join-Path $_.FullName 'Scripts\Activate.ps1')
        } | Select-Object -ExpandProperty Name
        return
    }
    $activator = Join-Path $Name 'Scripts\Activate.ps1'
    if (Test-Path $activator) { . $activator }
    else { Write-Error "No virtual environment '$Name' found in current directory." }
}

Register-ArgumentCompleter -CommandName activate -ParameterName Name -ScriptBlock {
    param($cmd, $param, $word)
    Get-ChildItem -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'Scripts\Activate.ps1') -and
        $_.Name -like "$word*"
    } | Select-Object -ExpandProperty Name
}
