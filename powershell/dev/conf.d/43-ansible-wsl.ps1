# =============================================================================
#  100-ansible-wsl.ps1
#  Routes ansible commands through WSL, activating a pyenv virtualenv first
#  and translating Windows paths to /mnt/<drive>/... automatically.
# =============================================================================

if (-not $script:AnsibleWslDistro) { $script:AnsibleWslDistro = 'debian' }
if (-not $script:AnsiblePyenvEnv)  { $script:AnsiblePyenvEnv  = 'dev'    }

# --- Path translation -------------------------------------------------------

function ConvertTo-WslPath {
    param([Parameter(Mandatory)] [string]$Path)
    $abs = try {
        (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        if ([IO.Path]::IsPathRooted($Path)) { $Path }
        else { Join-Path (Get-Location).Path $Path }
    }
    if ($abs -match '^([A-Za-z]):[\\/](.*)$') {
        return "/mnt/$($Matches[1].ToLower())/$($Matches[2] -replace '\\','/')"
    }
    return $abs
}

function Test-LooksLikePath {
    param([string]$s)
    if ([string]::IsNullOrEmpty($s)) { return $false }
    if ($s -match '^[A-Za-z]:[\\/]') { return $true }
    if ($s -match '[\\\/]')          { return $true }
    $pathExts = @('.yml','.yaml','.json','.ini','.cfg','.conf',
                  '.txt','.j2','.tmpl','.vault','.pass','.key','.pem')
    $ext = [IO.Path]::GetExtension($s)
    if ($pathExts -contains $ext.ToLower() -and (Test-Path -LiteralPath $s -ErrorAction SilentlyContinue)) {
        return $true
    }
    return $false
}

function Convert-AnsibleArg {
    param([string]$Arg)
    # --flag=value form
    if ($Arg -match '^(--[^=]+)=(.+)$') {
        $flag, $val = $Matches[1], $Matches[2]
        return if (Test-LooksLikePath $val) { "$flag=$(ConvertTo-WslPath $val)" } else { $Arg }
    }
    if ($Arg.StartsWith('-')) { return $Arg }
    # @file prefix
    $prefix, $val = '', $Arg
    if ($Arg.StartsWith('@')) { $prefix = '@'; $val = $Arg.Substring(1) }
    if (Test-LooksLikePath $val) { return $prefix + (ConvertTo-WslPath $val) }
    # key=value with path-like value
    if ($val -match '^([^=\s]+)=(.+)$') {
        $k, $v = $Matches[1], $Matches[2]
        if (Test-LooksLikePath $v) { return "$prefix$k=$(ConvertTo-WslPath $v)" }
    }
    return $Arg
}

function ConvertTo-BashSingleQuoted {
    param([string]$s)
    "'" + ($s -replace "'", "'\''") + "'"
}

# --- Dispatcher -------------------------------------------------------------

function Invoke-WslAnsible {
    param(
        [Parameter(Mandatory)] [string]   $Cmd,
        [string[]]                        $AnsibleArgs
    )
    $cwdWsl      = ConvertTo-WslPath (Get-Location).Path
    $translated  = $AnsibleArgs | ForEach-Object { Convert-AnsibleArg $_ }
    $quotedArgs  = ($translated | ForEach-Object { ConvertTo-BashSingleQuoted $_ }) -join ' '
    $bashCmd     = @(
        "cd $(ConvertTo-BashSingleQuoted $cwdWsl)",
        "export PYENV_VERSION=$script:AnsiblePyenvEnv",
        "$Cmd $quotedArgs"
    ) -join ' && '
    wsl.exe -d $script:AnsibleWslDistro -- bash -ic $bashCmd 2>&1 |
        Where-Object { $_ -notmatch 'no job control' }
    return $LASTEXITCODE
}

# --- Public commands --------------------------------------------------------

function ansible           { Invoke-WslAnsible -Cmd 'ansible'           -AnsibleArgs $args }
function ansible-playbook  { Invoke-WslAnsible -Cmd 'ansible-playbook'  -AnsibleArgs $args }
function ansible-galaxy    { Invoke-WslAnsible -Cmd 'ansible-galaxy'    -AnsibleArgs $args }
function ansible-vault     { Invoke-WslAnsible -Cmd 'ansible-vault'     -AnsibleArgs $args }
function ansible-lint      { Invoke-WslAnsible -Cmd 'ansible-lint'      -AnsibleArgs $args }
function ansible-config    { Invoke-WslAnsible -Cmd 'ansible-config'    -AnsibleArgs $args }
function ansible-doc       { Invoke-WslAnsible -Cmd 'ansible-doc'       -AnsibleArgs $args }
function ansible-inventory { Invoke-WslAnsible -Cmd 'ansible-inventory' -AnsibleArgs $args }
function ansible-console   { Invoke-WslAnsible -Cmd 'ansible-console'   -AnsibleArgs $args }
function ansible-pull      { Invoke-WslAnsible -Cmd 'ansible-pull'      -AnsibleArgs $args }
