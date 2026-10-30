# =============================================================================
#  00-environment.ps1
#  Env vars and encoding. Runs first so every later file sees them.
# =============================================================================

# UTF-8 everywhere — fixes Nerd Font icons and accented chars in completions
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# Editor: nano by default (dev layer switches to 'code --wait'); local.ps1 can set $NowhereEditor
$env:EDITOR = if ($NowhereEditor) { $NowhereEditor } else { 'nano' }
$env:VISUAL = $env:EDITOR

# Pager
$env:PAGER = 'less'
$env:LESS  = '-R -F -X'   # -R color passthrough, -F quit if one screen, -X no init

# Central virtualenv store — mirrors virtualenvwrapper convention
# uv venvs go here via mkvirtualenv; project-local .venv dirs are separate
$env:WORKON_HOME = Join-Path $HOME '.venvs'

# Local bin — scripts that live alongside the profile, available everywhere
# (core/bin and dev/bin are added to PATH by profile.ps1)

# Cache for generated init scripts and completions
$global:NowhereCacheDir =
    if ($env:LOCALAPPDATA)     { Join-Path $env:LOCALAPPDATA 'pwsh-completion-cache' }
    elseif ($env:XDG_CACHE_HOME) { Join-Path $env:XDG_CACHE_HOME 'pwsh-completion-cache' }
    else                       { Join-Path $HOME '.cache/pwsh-completion-cache' }

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

# ConfCrypt: machine-specific, set $env:CONFCRYPT_HOME in local.ps1 (no default)
