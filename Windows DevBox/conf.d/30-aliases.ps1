# =============================================================================
#  30-aliases.ps1
#  Wrappers for eza, git, kubectl, docker, helm, terraform/tofu, and misc.
#  PS aliases can't pass arguments, so functions are used throughout.
#  All external-tool checks are batched into one Get-Command call.
# =============================================================================

$_ext = [System.Collections.Generic.HashSet[string]]::new(
    [string[]](
        Get-Command eza, kubectl, helm, docker, terraform, tofu `
            -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name |
            ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

# --- eza (replaces ls; icons and git status built in) -----------------------
if ($_ext.Contains('eza')) {
    Remove-Alias ls -Force -ErrorAction SilentlyContinue
    function ls  { eza --icons --group-directories-first @args }
    function ll  { eza -l  --icons --group-directories-first --git @args }
    function la  { eza -la --icons --group-directories-first --git @args }
    function lt  { eza --tree --icons --level=2 @args }
    function llt { eza -l  --tree --icons --level=2 --git @args }
}

# --- Git --------------------------------------------------------------------
function g     { git @args }
function gst   { git status @args }
function gss   { git status -s @args }
function ga    { git add @args }
function gaa   { git add --all @args }
function gc    { git commit -v @args }
function gcmsg { git commit -m @args }
function gca   { git commit -v --amend @args }
function gco   { git checkout @args }
function gcb   { git checkout -b @args }
function gcm   { git checkout main @args }
function gd    { git diff @args }
function gds   { git diff --staged @args }
function gp    { git push @args }
function gpf   { git push --force-with-lease @args }
function gl    { git pull @args }
function gf    { git fetch --all --prune @args }
function gb    { git branch @args }
function gbd   { git branch -d @args }
function glog  { git log --oneline --decorate --graph @args }
function gloga { git log --oneline --decorate --graph --all @args }
function grb   { git rebase @args }
function grbi  { git rebase -i @args }
function gsta  { git stash push @args }
function gstp  { git stash pop @args }
function gcl   {
    git clone @args
    if ($LASTEXITCODE -eq 0) {
        Set-Location (($args[-1] -split '/')[-1] -replace '\.git$', '')
    }
}

# --- Kubernetes -------------------------------------------------------------
if ($_ext.Contains('kubectl')) {
    Set-Alias -Name k -Value kubectl
    function kgp  { kubectl get pods @args }
    function kgs  { kubectl get svc @args }
    function kgd  { kubectl get deployments @args }
    function kgn  { kubectl get nodes @args }
    function kga  { kubectl get all @args }
    function kd   { kubectl describe @args }
    function kl   { kubectl logs -f @args }
    function kex  { kubectl exec -it @args }
    function kctx { kubectl config use-context @args }
    function kns  {
        param($namespace)
        $ns = if ($namespace -in 'default', 'd') { 'default' } else { $namespace }
        kubectl config set-context --current --namespace=$ns
    }
}

# --- Helm -------------------------------------------------------------------
if ($_ext.Contains('helm')) {
    Remove-Alias h -Force -ErrorAction SilentlyContinue
    Set-Alias -Name h -Value helm
}

# --- Docker -----------------------------------------------------------------
if ($_ext.Contains('docker')) {
    function dc   { docker compose @args }
    function dcup { docker compose up -d @args }
    function dcdn { docker compose down @args }
    function dcl  { docker compose logs -f @args }
    function dcr  { docker compose restart @args }
    function dcps { docker compose ps @args }
    function dcb  { docker compose build @args }
    function dcpl { docker compose pull @args }
    function dce  { docker compose exec @args }
    function dps  { docker ps @args }
}

# --- Terraform / OpenTofu ---------------------------------------------------
if ($_ext.Contains('terraform')) {
    function tf  { terraform @args }
    function tfi { terraform init @args }
    function tfp { terraform plan @args }
    function tfa { terraform apply @args }
    function tfd { terraform destroy @args }
    function tff { terraform fmt -recursive @args }
}
if ($_ext.Contains('tofu')) {
    function to  { tofu @args }
    function toi { tofu init @args }
    function top { tofu plan @args }
    function toa { tofu apply @args }
}

# --- Navigation -------------------------------------------------------------
function ..    { Set-Location .. }
function ...   { Set-Location ../.. }
function ....  { Set-Location ../../.. }
function ..... { Set-Location ../../../.. }

# --- Misc -------------------------------------------------------------------
function which { Get-Command @args | Select-Object -ExpandProperty Source }
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

function List-COM { Get-PnpDevice -Class Ports -PresentOnly | select FriendlyName, Status }

Remove-Variable _ext


