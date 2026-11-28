# Real-machine checklist

The sandboxed suites (`tests/`) prove the files and the shared parity list. They cannot prove a real machine feels right. Run this once per role after bootstrapping, and again after large changes. Tick each box; note failures as issues.

## Every role (do these first)

- [ ] Clone the repo and run the role's bootstrap (`bootstrap.ps1` or `bootstrap.sh`, `devbox`, `user` or `server`). It finishes without errors.
- [ ] Run bootstrap a second time. It reports nothing to do and changes nothing.
- [ ] Open a new shell. No errors, no warnings, at most the one "run bootstrap" hint (and none if everything is installed).
- [ ] Prompt is the segmented Starship prompt, with icons rendering (font set in the terminal). Switching the terminal between a dark and a light color scheme recolors the prompt and the command line.
- [ ] `~/.config/nowhere/local.ps1` or `local.zsh` exists, owner-only, and was not overwritten by the second bootstrap.
- [ ] No `~/.config/nowhere/theme.ps1` or `theme.zsh` exists after bootstrap. Writing one that sets a single color (``Set-PSReadLineOption -Colors @{ Comment = "`e[33m" }``, or `ZSH_HIGHLIGHT_STYLES[comment]=fg=yellow`) and opening a new shell changes that color and nothing else; deleting it brings the old color back.
- [ ] `git config core.hooksPath` prints `.githooks`. Staging a fake secret and committing is blocked by gitleaks.
- [ ] Core commands exist: `reload`, `editp`, `aliases`, `update`, `goto`, `mkcd`, `gcl`, `workon`, `..` to `.....`. With eza: `ll`, `la`, `lt`. With git: `gst`, `gco`, `glog`.
- [ ] `echo $EDITOR` (`$env:EDITOR`) matches the role: `code --wait` on a DevBox, `nano` on a User machine or a Server.
- [ ] Keybindings: Up/Down search history by prefix, Ctrl+R opens fzf history, Tab shows menu completion, autosuggestions appear in grey.
- [ ] `z <dir>` (zoxide) jumps after visiting a directory twice.
- [ ] `reload` re-sources the profile without errors.
- [ ] `uv --version` works.
- [ ] A local override value takes effect (for example `NowhereEditor='vim'` then `reload`).

## Windows DevBox

- [ ] PowerShell 7 is the shell; `$PROFILE` stub sets `NOWHERE_ROLE = 'devbox'`.
- [ ] Pinned modules from `powershell/modules.json` are installed (`Get-Module -ListAvailable`).
- [ ] Dev layer: `topl` (with tofu), `tfp`, `kgp`, `dcup` exist only when their tools are installed.
- [ ] `ansible-playbook --version` runs inside the WSL distro named in the override (default `debian`); a Windows path argument is translated.
- [ ] `update` (as administrator) runs Windows Update, winget, `uv self update` plus pins (uv tools and modules), WSL and disk cleanup and reports each step.
- [ ] No MOTD banner is shown.

## Windows User

- [ ] `$PROFILE` stub sets `NOWHERE_ROLE = 'user'`; dev aliases (`topl`, `tfp`, `kgp`, `dcup`) and `ansible-playbook` are absent, even with their tools installed.
- [ ] No dev tools were installed (kubectl, helm, docker, terraform, tofu, gh, VS Code) and no `server-motd` (`uv tool list`).
- [ ] `update` (as administrator) runs Windows Update, winget, `uv self update` plus pins, and disk cleanup, but not WSL; `update -WSL` is opt-in.
- [ ] No MOTD banner is shown.

## Windows Server

- [ ] `$PROFILE` stub sets `NOWHERE_ROLE = 'server'`; dev aliases (`topl`, `tfp`, `kgp`, `dcup`) are absent.
- [ ] On Server 2022 or older: bootstrap warned about winget, listed the tools to install by hand, and still finished uv, `server-motd`, stub and override.
- [ ] `server-motd` is on PATH at the pinned version (`uv tool list`). `%ProgramData%\server-motd\config.toml` exists, owner-only.
- [ ] The MOTD banner prints on login in an interactive session, and not in the output of a non-interactive SSH command (`ssh host Get-Date`).
- [ ] Over SSH (OpenSSH with PowerShell as DefaultShell) the same banner and prompt appear.
- [ ] `update` runs Windows Update, winget (if present) and the pins (server-motd at its pin) only; `update -WSL` and `-DiskCleanup` are opt-in.
- [ ] `server-motd install-profile` was not run, and the profile contains exactly one MOTD hook (no double banner).

## Linux DevBox

- [ ] `~/.zshrc` stub sets `NOWHERE_ROLE=devbox`; `echo $SHELL` is zsh (run `chsh -s $(command -v zsh)` if not).
- [ ] ZSH plugins exist at the pinned SHAs under `~/.local/share/nowhere/plugins` (autosuggestions, substring search, syntax highlighting).
- [ ] Syntax highlighting uses the terminal's colors: commands blue, strings green, comments dim; typing an invalid command turns red.
- [ ] Dev layer aliases (`topl`, `tfp`, `kgp`, `dcup`) exist only with their tools; helm, terraform and tofu came from the pinned releases (`~/.local/bin`); `code` is devbox-manual (install it by hand) and is skipped without errors until you do.
- [ ] `bat`/`fd` work even though Debian names them `batcat`/`fdfind`.
- [ ] `update` runs apt, brings release binaries and plugins to their pins, and runs `uv self update`; a failing step does not stop the others.
- [ ] No MOTD banner from Nowhere is shown.

## Linux User

- [ ] `~/.zshrc` stub sets `NOWHERE_ROLE=user`; `echo $SHELL` is zsh; dev aliases are absent.
- [ ] No dev tools were installed (no helm, terraform or tofu in `~/.local/bin`) and no `server-motd`, `/etc/update-motd.d/50-server-motd` or `/etc/server-motd`.
- [ ] `update` runs apt, brings release binaries and plugins to their pins, and runs `uv self update`.
- [ ] No MOTD banner from Nowhere is shown.
- [ ] On Linux Mint 22 (Ubuntu 24.04 based, not yet supported): bootstrap and `bash tests/zsh/run.sh` pass. Once they do, add Mint to the supported list in the README and `shared/tools.json`.

## Linux Server

- [ ] `~/.zshrc` stub sets `NOWHERE_ROLE=server`; dev aliases are absent.
- [ ] `server-motd` is installed at the pinned version; `/etc/server-motd/config.toml` exists, mode 600.
- [ ] `/etc/update-motd.d/50-server-motd` exists, root-owned, mode 755, and runs the binary by absolute path. The binary is `/usr/local/bin/server-motd` and is root-owned (not under a user's home); the hook exits silently if it is removed.
- [ ] A fresh SSH login (PAM session) shows the MOTD exactly once. The ZSH profile prints no second banner.
- [ ] Non-interactive SSH commands (`ssh host true`) print nothing extra.
- [ ] Debian 13+ or Ubuntu 24.04+: the apt installs (notably eza and hexyl) succeeded, and starship, carapace and gitleaks are in `~/.local/bin` from the pinned releases. A new shell prints no "run bootstrap" hint.
- [ ] `update` runs apt, the pins (release binaries, server-motd, plugins) and `uv self update`.

## Cross-role feel check

Open one shell per role side by side and compare: prompt look, `ll` output, `gst`, `goto`, Tab completion behaviour, history search, `update` name, `EDITOR`. Anything that differs without a role reason is a parity bug: add it to `tests/parity.txt` if it is a command or env value.
