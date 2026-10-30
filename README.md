# Nowhere

My personal environment for all my machines: shell profiles, scripts, and tooling config, organized by machine role.

## Status

Nowhere is being designed before it is built. The direction and every open decision live in the wayfinder map, [issue #1](https://github.com/mookeyj79/Nowhere/issues/1). Only the Windows DevBox profile exists so far; the other three roles are not started.

The four roles are Windows DevBox, Windows Server, Linux DevBox and Linux Server. A **core** layer is shared by all four, and a **dev layer** is added only on DevBoxes. Terms are defined in [`GLOSSARY.md`](GLOSSARY.md).

## Layout

| Path | Contents |
| --- | --- |
| `powershell/`, `shared/` | PowerShell profile (core and dev layers) and the shared Starship config |
| `tests/` | Pester tests (sandboxed `pwsh` session) |
| `docs/` | Agent and workflow docs (issue tracker, triage labels, domain) |
| `scripts/` | Wayfinder helpers: `frontier.sh`, `map-append.sh`, `resolve.sh` |
| `.githooks/`, `.github/` | gitleaks pre-commit hook and CI (gitleaks, shellcheck) |

Decided but not built yet: files organised by shell (`shared/`, `powershell/`, `zsh/`, each split into core and dev), a per-OS bootstrap script with a pinned tool manifest, and an untracked per-machine local override in `~/.config/nowhere/` for paths, tokens and similar values.

## Contributing

Enable the secrets hook once per clone: `git config core.hooksPath .githooks`. It needs [gitleaks](https://github.com/gitleaks/gitleaks) installed, and blocks commits that stage secrets.

## PowerShell profile

A modular PowerShell 7 profile under `powershell/`. A few-line stub at `$PROFILE` sets `$env:NOWHERE_ROLE` (`devbox` or `server`) and dot-sources `powershell/profile.ps1`. That entry point dot-sources the local override `~/.config/nowhere/local.ps1` first, then `core/conf.d/*.ps1` plus, on `devbox` only, `dev/conf.d/*.ps1`, merged in one filename order. Any other role (or none) gets core only.

| File | Purpose |
| --- | --- |
| `core/conf.d/00-environment.ps1` | UTF-8 encoding, `EDITOR`/`PAGER`, `WORKON_HOME`, merged `KUBECONFIG` |
| `core/conf.d/10-line-editor.ps1` | PSReadLine: history prediction, Emacs mode, key bindings |
| `core/conf.d/20-completions.ps1` | Tab completion via Carapace and native tool completers, cached by binary mtime |
| `core/conf.d/30-aliases.ps1` | One-liners: eza, git, navigation |
| `core/conf.d/35-helpers.ps1` | Functions with logic: `gcl`, `touch`, `mkcd`, `wget`, `List-COM` (Windows only) |
| `core/conf.d/40-profile.ps1` | `reload`, `editp`, `update`, `aliases` |
| `core/conf.d/41-goto.ps1`, `42-venv.ps1` | `goto` bookmarks, uv virtualenv helpers |
| `core/conf.d/50-init.ps1` | zoxide and Starship init. Must load before anything that touches the prompt, because Starship overwrites it |
| `core/conf.d/60-motd.ps1` | Server role only: runs `server-motd` at login when it is on `PATH` |
| `dev/conf.d/01-dev-environment.ps1` | `EDITOR` = `code --wait` |
| `dev/conf.d/31-dev-aliases.ps1` | kubectl, helm, docker, terraform/tofu wrappers (OpenTofu plan is `topl`) |
| `dev/conf.d/43-ansible-wsl.ps1` | Runs `ansible*` commands inside WSL and translates Windows paths |

Other contents:

- `powershell/local.ps1.example`: template for the per-machine override. Every key is optional and read with a default.
- `powershell/core/bin/Update-System.ps1`: one-shot updater for Windows Update, winget, WSL, and disk cleanup (`update`). Run it as administrator.
- `shared/starship.toml`: the single Catppuccin Starship prompt.
- `powershell/powershell.config.json`: sets the execution policy to `RemoteSigned`.
- `Modules/`: vendored PowerShell modules. Git-ignored; bootstrap will install them from a pinned manifest.
- `tests/powershell/`: Pester tests that run a real `pwsh` against a throwaway HOME. Run `Invoke-Pester tests/powershell` (Pester 5+).
Optional tools the profile uses when they are installed: eza, zoxide, Starship, Carapace, kubectl, helm, docker, gh, terraform/tofu, uv.

## Windows Server role

`bootstrap/bootstrap.ps1 server` readies a Windows Server with the core layer only (no dev layer, no dev tools) plus the `server-motd` login banner.

- `server-motd` is installed with `uv tool install server-motd==<version>`; the version is pinned under `uvTools` in `shared/tools.json`. Bootstrap skips the install when that version is already present.
- `config.toml` is seeded from `shared/server-motd/config.toml.example` to `%ProgramData%\server-motd\config.toml` with owner-only permissions, and never overwritten.
- The profile (`powershell/core/conf.d/60-motd.ps1`) runs `server-motd` only on the `server` role and only when it is on `PATH`. DevBoxes never show it.
- `server-motd install-profile` and `uninstall-profile` are not used on Nowhere machines. The profile above is the only hook, so the stub keeps a single owner.
- Editions without winget (Windows Server 2022 and older): bootstrap warns, skips the core tool install and carries on with uv, `server-motd`, modules, the stub and the override. Install the listed tools by hand, or use a Server 2025 image, which ships winget.
- `update` on a server runs Windows Update and, when winget exists, winget. WSL and disk cleanup (cleanmgr is absent without Desktop Experience) are not part of the default there; pass `-WSL` or `-DiskCleanup` explicitly.
