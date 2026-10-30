# =============================================================================
#  31-dev-aliases.zsh  (dev layer: devbox only)
#  kubectl, helm, docker, terraform/tofu one-liners, each guarded by tool
#  presence. Mirrors powershell/dev/conf.d/31-dev-aliases.ps1.
# =============================================================================

if nowhere_tool kubectl; then
    alias k='kubectl'
    alias kgp='kubectl get pods'
    alias kgs='kubectl get svc'
    alias kgd='kubectl get deployments'
    alias kgn='kubectl get nodes'
    alias kga='kubectl get all'
    alias kd='kubectl describe'
    alias kl='kubectl logs -f'
    alias kex='kubectl exec -it'
    alias kctx='kubectl config use-context'
fi

nowhere_tool helm && alias h='helm'

if nowhere_tool docker; then
    alias dc='docker compose'
    alias dcup='docker compose up -d'
    alias dcdn='docker compose down'
    alias dcl='docker compose logs -f'
    alias dcr='docker compose restart'
    alias dcps='docker compose ps'
    alias dcb='docker compose build'
    alias dcpl='docker compose pull'
    alias dce='docker compose exec'
    alias dps='docker ps'
fi

if nowhere_tool terraform; then
    alias tf='terraform'
    alias tfi='terraform init'
    alias tfp='terraform plan'
    alias tfa='terraform apply'
    alias tfd='terraform destroy'
    alias tff='terraform fmt -recursive'
fi
if nowhere_tool tofu; then
    alias to='tofu'
    alias toi='tofu init'
    alias topl='tofu plan'
    alias toa='tofu apply'
fi
true
