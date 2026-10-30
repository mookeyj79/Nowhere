# =============================================================================
#  30-aliases.ps1
#  One-liner wrappers for eza and git, navigation, which.
#  PS aliases can't pass arguments, so functions are used throughout.
#  All external-tool checks are batched into one Get-Command call.
# =============================================================================

$_ext = [System.Collections.Generic.HashSet[string]]::new(
    [string[]](
        Get-Command eza `
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

# --- Navigation -------------------------------------------------------------
function ..    { Set-Location .. }
function ...   { Set-Location ../.. }
function ....  { Set-Location ../../.. }
function ..... { Set-Location ../../../.. }

# --- Misc -------------------------------------------------------------------
function which { Get-Command @args | Select-Object -ExpandProperty Source }


Remove-Variable _ext

