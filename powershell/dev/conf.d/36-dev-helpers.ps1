# =============================================================================
#  36-dev-helpers.ps1  (dev layer: devbox only)
#  Dev-layer functions with logic.
# =============================================================================

# --- kns: switch the current kubectl namespace (d / default -> default) -----
if (Test-NowhereTool kubectl) {
    function kns {
        param($namespace)
        $ns = if ($namespace -in 'default', 'd') { 'default' } else { $namespace }
        kubectl config set-context --current --namespace=$ns
    }
}
