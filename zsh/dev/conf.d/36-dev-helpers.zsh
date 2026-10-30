# =============================================================================
#  36-dev-helpers.zsh  (dev layer: devbox only)
#  Dev-layer functions with logic. Mirrors powershell/dev/conf.d/36-dev-helpers.ps1.
# =============================================================================

# --- kns: switch the current kubectl namespace (d / default -> default) -----
if nowhere_tool kubectl; then
    kns() {
        local ns=$1
        [[ $ns == d ]] && ns=default
        kubectl config set-context --current --namespace=$ns
    }
fi
true