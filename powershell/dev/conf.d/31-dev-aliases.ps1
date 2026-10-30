# =============================================================================
#  31-dev-aliases.ps1  (dev layer: devbox only)
#  kubectl, helm, docker, terraform/tofu one-liners, each guarded by tool
#  presence. Logic (kns) lives in 36-dev-helpers.
# =============================================================================

# --- Kubernetes -------------------------------------------------------------
if (Test-NowhereTool kubectl) {
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
}

# --- Helm -------------------------------------------------------------------
if (Test-NowhereTool helm) {
    Remove-Alias h -Force -ErrorAction SilentlyContinue
    Set-Alias -Name h -Value helm
}

# --- Docker -----------------------------------------------------------------
if (Test-NowhereTool docker) {
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
if (Test-NowhereTool terraform) {
    function tf  { terraform @args }
    function tfi { terraform init @args }
    function tfp { terraform plan @args }
    function tfa { terraform apply @args }
    function tfd { terraform destroy @args }
    function tff { terraform fmt -recursive @args }
}
if (Test-NowhereTool tofu) {
    function to   { tofu @args }
    function toi  { tofu init @args }
    function topl { tofu plan @args }
    function toa  { tofu apply @args }
}
