# Nowhere

My personal shell environment: one setup that feels the same on every machine I log into. PowerShell on Windows, ZSH on Linux. Terms are defined in [`GLOSSARY.md`](GLOSSARY.md); the design history and decisions live in the wayfinder map, [issue #1](https://github.com/mookeyj79/Nowhere/issues/1).

## Roles

Four roles: Windows DevBox, Windows Server, Linux DevBox, Linux Server. A **core** layer is shared by all four; the **dev layer** is added only on a DevBox. Servers also get the `server-motd` login banner.

| Role | Shell | Layers | Bootstrap | `EDITOR` | Notes |
| --- | --- | --- | --- | --- | --- |
| Windows DevBox | PowerShell 7 | core + dev | `bootstrap/bootstrap.ps1 devbox` | `code --wait` | kubectl/helm/docker/terraform/tofu aliases, Ansible via WSL |
| Windows Server | PowerShell 7 | core | `bootstrap/bootstrap.ps1 server` | `nano` | `server-motd` at login, `update` = Windows Update + winget |
| Linux DevBox | ZSH | core + dev | `bootstrap/bootstrap.sh devbox` | `code --wait` | dev aliases, tools guarded by presence |
| Linux Server | ZSH | core | `bootstrap/bootstrap.sh server` | `nano` | `server-motd` via the root `update-motd.d` hook |

The role is set by the stub (below). A missing or unknown role behaves as `server`. Linux support: Debian 13+ and Ubuntu 24.04+.

## Setup

Clone the repo anywhere, then run the bootstrap for the machine's role. It is idempotent: re-running changes nothing that is already done.

```powershell
# Windows (PowerShell 7, from the clone)
pwsh -File bootstrap/bootstrap.ps1 devbox     # or: server
```

```sh
# Linux (Debian/Ubuntu, from the clone)
bash bootstrap/bootstrap.sh devbox            # or: server
```

Bootstrap installs tools from `shared/tools.json` (winget on Windows, apt plus checksum-pinned release binaries on Linux: starship, carapace and gitleaks, and on a devbox helm, terraform and tofu; core always, dev tools on a devbox). It installs `uv` with Astral's official installer if absent, installs pinned PowerShell modules or ZSH plugins, writes the **stub**, seeds the **local override**, points `core.hooksPath` at `.githooks` (the gitleaks pre-commit hook), and on a server installs `server-motd`. The header of each bootstrap script lists its exact steps. Open a new shell afterwards.

Two modules in `bootstrap/lib/` do the manifest work for bootstrap and `update` alike. The **install plan** (`plan.sh`, `Plan.ps1`) reads the manifests and lists what a role needs, without installing anything. **Pins** (`pins.sh`, `Sync-Pins.ps1`) bring the machine to every pin in that plan: release binaries, uv tools, ZSH plugins or PowerShell modules. Bootstrap runs pins strictly and stops at the first failure; `update` reports each failure and carries on.

If a tool, module or plugin is missing, the profile starts silently and prints one hint to run bootstrap.

`code` (VS Code) has no headless Linux install route, so on a Linux DevBox it is **devbox-manual**: install it by hand. The dev layer skips it when absent, and the `EDITOR` default of `code --wait` only makes sense once it is there. Every core tool has a route, so the "run bootstrap" hint clears after bootstrap.

Windows Server 2022 and older have no winget: bootstrap warns, skips only the core tool install, and carries on; install the listed tools by hand or use a Server 2025 image.

## Layout

| Path | Contents |
| --- | --- |
| `shared/` | Shell-neutral files: `starship.toml` (the one Catppuccin Macchiato prompt), `tools.json` (tool manifest, `uvTools` pins), `core-tools.txt` (the tools whose absence gives the bootstrap hint), `server-motd/config.toml.example` |
| `powershell/` | `profile.ps1` entry point, `core/` and `dev/` each with `conf.d/` (numbered files, merged in one filename order), `core/bin/` (`Update-System.ps1`, on PATH), `core/lib/` (`UpdateSystem.ps1`, the testable part of `update`), `modules.json` (pinned modules), `powershell.config.json`, `local.ps1.example` |
| `zsh/` | The same shape: `profile.zsh`, `core/` and `dev/` with `conf.d/`, `core/bin/` (`update`), `plugins.json` (plugins pinned by SHA, no plugin manager), `local.zsh.example` |
| `bootstrap/` | `bootstrap.ps1` (Windows), `bootstrap.sh` (Linux), and `lib/` with the install plan and pins for each OS |
| `tests/` | Sandboxed suites for both shells and the shared parity list (see Tests) |
| `docs/` | Agent docs and the [real-machine checklist](docs/real-machine-checklist.md) |
| `scripts/` | Wayfinder helpers for the issue map: `add-blocker.sh`, `frontier.sh`, `map-append.sh`, `resolve.sh` |
| `.githooks/`, `.github/` | gitleaks pre-commit hook; CI (gitleaks, shellcheck, Pester, zsh harness) |

conf.d numbering (same on both shells): `00` environment, `10` line editor, `20` completions, `30` aliases (one-liners only), `35` helpers (logic), `40` profile commands (`reload`, `editp`, `update`, `aliases`), `41` goto, `42` venv helpers, `50` init (zoxide, Starship), `60` MOTD (PowerShell server only), `90` syntax highlighting (ZSH). Dev layer files use the `01`, `31`, `36`, `43` slots.

## Stub and local override

- **Stub**: a few lines at `$PROFILE` (PowerShell) or `~/.zshrc` (ZSH) that set `NOWHERE_ROLE` (`devbox` or `server`) and source the profile from the clone. Bootstrap writes it and backs up a different existing one.
- **Local override**: `~/.config/nowhere/local.ps1` or `local.zsh`, outside the repo and never committed, sourced before any conf.d file. It holds machine-specific values: `NOWHERE_HOME`, the editor, `goto` bookmarks, the WSL distro, tokens. Every key is optional and read with a default. Bootstrap seeds it from `local.ps1.example` / `local.zsh.example` with owner-only permissions and never overwrites it.

## Servers and the MOTD

Servers show `server-motd`, installed with `uv tool install "server-motd @ git+https://github.com/mookeyj79/Server-MOTD@<commit>"` (it is not on PyPI; the commit pin is in `shared/tools.json` under `uvTools`, and bootstrap and `update` both reinstall when the installed pin differs). `server-motd install-profile` and `uninstall-profile` are not used on Nowhere machines, so the hook has a single owner:

- Windows Server: the PowerShell profile (`60-motd.ps1`) runs it on the `server` role, in interactive login sessions only: `ssh host cmd` (`pwsh -c`), Ansible (`-NonInteractive -EncodedCommand`), `-File` scripts and redirected output never get the banner in their output. Config at `%ProgramData%\server-motd\config.toml`.
- Linux Server: bootstrap writes `/etc/update-motd.d/50-server-motd`, which runs the binary by absolute path. Config at `/etc/server-motd/config.toml`. The ZSH profile never calls it. The hook runs as root, so on Linux `server-motd` is installed system-wide with sudo (`UV_TOOL_DIR=/opt/nowhere/uv-tools`, binary in `/usr/local/bin`, both root-owned) instead of under the installing user's home, where root would be running a user-writable file. The hook also exits quietly if the binary is missing, so a broken install cannot break a login.

Both configs are seeded from `shared/server-motd/config.toml.example`, mode owner-only, never overwritten. DevBoxes never show the MOTD.

## `update`

The one maintenance name on every role. On Windows it runs `Update-System`, which needs an elevated session: Windows Update, winget, Tools (`uv self update`, then pins: uv tools and PowerShell modules), WSL, and disk cleanup. Switches (`-Windows`, `-Winget`, `-Tools`, `-WSL`, `-DiskCleanup`) pick individual steps. On a server a bare `update` skips WSL and disk cleanup, which stay available as explicit switches. `Update-PSProfile` runs only the pins and needs no elevation. On Linux it runs `zsh/core/bin/update`: apt, then pins (release binaries, uv tools, ZSH plugins), then `uv self update`. It is the only thing besides bootstrap that installs or upgrades, and it never moves anything past its pin.

## Tests

- `tests/zsh/run.sh`: real `zsh` against a throwaway HOME with a fake apt/curl. Needs `zsh` and `jq`. Run `bash tests/zsh/run.sh [scenario-id ...]`.
- `tests/powershell/`: Pester 5.5+ against a real `pwsh` in a throwaway HOME. Run `Invoke-Pester tests/powershell` (slow, several minutes). Pester result files (`testResults.xml`) are git-ignored; CI writes its own to the runner's temp directory.
- `tests/scenarios.txt` (and `tests/zsh/scenarios-*.txt`) lists the scenario ids and their pwsh counterparts; `Parity.Tests.ps1` checks that every counterpart it names exists. `tests/parity.txt` is the one list **both** suites read (`Parity.Tests.ps1` and `scenarios-parity.sh`): core command names, role gating, `EDITOR` defaults, and missing-tool silence must be identical in pwsh and zsh. Add a line there to extend the parity contract.
- `tests/uvtools-smoke.sh`: installs every `uvTools` pin in the install plan with the real `uv` (network) and runs its `--help`, since both sandboxes fake `uv`. Needs `uv`, `jq` and `bash`.
- CI (`.github/workflows/gitleaks.yml`) runs gitleaks, shellcheck, Pester on Windows, the zsh harness on Ubuntu, and the uvTools smoke test on both.

The sandboxes cannot show that a real machine feels right; use [`docs/real-machine-checklist.md`](docs/real-machine-checklist.md) after bootstrapping each role.

## Committing

This is a personal setup, shared for reference: fork it and adapt it rather than sending pull requests.

Bootstrap enables the secrets hook. On a clone you did not bootstrap, run `git config core.hooksPath .githooks`; it needs [gitleaks](https://github.com/gitleaks/gitleaks) installed.
