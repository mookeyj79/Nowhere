# Nowhere

My personal environment for all my machines: shell profiles, scripts, and tooling config, organized by machine role.

## Status

Nowhere is being designed before it is built. The direction and every open decision live in the wayfinder map, [issue #1](https://github.com/mookeyj79/Nowhere/issues/1). Only the Windows DevBox profile exists so far; the other three roles are not started.

The four roles are Windows DevBox, Windows Server, Linux DevBox and Linux Server. A **core** layer is shared by all four, and a **dev layer** is added only on DevBoxes. Terms are defined in [`GLOSSARY.md`](GLOSSARY.md).

## Layout

| Path | Contents |
| --- | --- |
| `Windows DevBox/` | The existing PowerShell profile. It moves under `powershell/` once the planned layout is built |
| `docs/` | Agent and workflow docs (issue tracker, triage labels, domain) |
| `scripts/` | Wayfinder helpers: `frontier.sh`, `map-append.sh`, `resolve.sh` |
| `.githooks/`, `.github/` | gitleaks pre-commit hook and CI (gitleaks, shellcheck) |

Decided but not built yet: files organised by shell (`shared/`, `powershell/`, `zsh/`, each split into core and dev), a per-OS bootstrap script with a pinned tool manifest, and an untracked per-machine local override in `~/.config/nowhere/` for paths, tokens and similar values.

## Contributing

Enable the secrets hook once per clone: `git config core.hooksPath .githooks`. It needs [gitleaks](https://github.com/gitleaks/gitleaks) installed, and blocks commits that stage secrets.

## Windows DevBox

A modular PowerShell 7 profile. `profile.ps1` is the `$PROFILE` entry point. It dot-sources every `conf.d/*.ps1` file, then every `profile.d/*.ps1` file, each in name order, so you can enable or disable a feature by adding or removing a file.

| File | Purpose |
| --- | --- |
| `conf.d/00-environment.ps1` | UTF-8 encoding, `EDITOR`/`PAGER`, `WORKON_HOME`, `bin/` on `PATH`, merged `KUBECONFIG` |
| `conf.d/10-psreadline.ps1` | PSReadLine: history prediction, Emacs mode, key bindings |
| `conf.d/20-completions.ps1` | Tab completion via Carapace and native tool completers, cached by binary mtime |
| `conf.d/30-aliases.ps1` | Wrappers for eza, git, kubectl, docker, helm, and terraform/tofu |
| `conf.d/40-functions.ps1` | Profile management (`reload`, `editp`), `goto` bookmarks, uv virtualenv helpers |
| `conf.d/50-init.ps1` | zoxide and Starship init. Must load last because Starship overwrites the prompt |

Other contents:

- `profile.d/100-ansible-wsl.ps1`: runs `ansible*` commands inside WSL (Debian, pyenv `dev` env) and translates Windows paths to `/mnt/<drive>/...`. Override the defaults by setting `$script:AnsibleWslDistro` and `$script:AnsiblePyenvEnv` before it loads.
- `bin/Update-System.ps1`: one-shot updater for Windows Update, winget, WSL, and disk cleanup. Run it as administrator. Use `-Windows`, `-Winget`, `-WSL`, or `-DiskCleanup` to run a single step.
- `starship.toml`: Catppuccin-themed Starship prompt.
- `powershell.config.json`: sets the execution policy to `RemoteSigned`.
- `Modules/`: vendored PowerShell modules (Catppuccin, PSWindowsUpdate, QRCodeGenerator, powershell-yaml). Git-ignored and not in the repo; bootstrap will install them from a pinned manifest.

### Setup

Copy or symlink the contents of `Windows DevBox/` into the directory that holds your `$PROFILE`. Run `Split-Path $PROFILE -Parent` in pwsh to find it. Rename `profile.ps1` to match `$PROFILE`, usually `Microsoft.PowerShell_profile.ps1`.

Optional tools the profile uses when they are installed: eza, zoxide, Starship, Carapace, kubectl, helm, docker, gh, terraform/tofu, uv.
