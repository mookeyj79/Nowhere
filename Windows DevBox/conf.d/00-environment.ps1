# =============================================================================
#  00-environment.ps1
#  Env vars and encoding. Runs first so every later file sees them.
# =============================================================================

# UTF-8 everywhere — fixes Nerd Font icons and accented chars in completions
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# Default editor
$env:EDITOR = 'code'
$env:VISUAL = $env:EDITOR

# Pager
$env:PAGER = 'less'
$env:LESS  = '-R -F -X'   # -R color passthrough, -F quit if one screen, -X no init

# Central virtualenv store — mirrors virtualenvwrapper convention
# uv venvs go here via mkvirtualenv; project-local .venv dirs are separate
$env:WORKON_HOME = Join-Path $HOME '.venvs'

# Local bin — scripts that live alongside the profile, available everywhere
$_binDir = Join-Path (Split-Path $PROFILE -Parent) 'bin'
if (Test-Path $_binDir) { $env:PATH = "$_binDir;$env:PATH" }
Remove-Variable _binDir

# Multi-context kubeconfig — merges every config / *.yaml / *.yml in ~/.kube
$kubeDir = Join-Path $HOME '.kube'
if (Test-Path $kubeDir) {
    $configs  = Get-ChildItem $kubeDir -Filter 'config' -File -ErrorAction SilentlyContinue
    $configs += Get-ChildItem $kubeDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue
    $configs += Get-ChildItem $kubeDir -Filter '*.yml'  -File -ErrorAction SilentlyContinue
    if ($configs) {
        $env:KUBECONFIG = ($configs.FullName -join [IO.Path]::PathSeparator)
    }
}

# ConfCrypt
$env:CONFCRYPT_HOME = "D:\Dev\Homelab\Scripts\confcrypt"
