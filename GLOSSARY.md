# Nowhere

A personal shell environment: one setup that feels the same on every machine I log into.

## Language

**Role**:
What a machine is for: DevBox or Server, on Windows or Linux. Four roles in all.
_Avoid_: machine type, profile type

**Core**:
The layer of tools, aliases, keybindings and theme shared by all four roles.
_Avoid_: base, common

**Dev layer**:
What a DevBox adds on top of the core; Servers do not load it.
_Avoid_: extras, dev tools

**Shared**:
Files that are not tied to any shell and serve both PowerShell and ZSH, such as the prompt config and the tool manifest.
_Avoid_: common, global

**Bootstrap**:
The re-runnable per-OS script that readies a fresh machine for its role.
_Avoid_: installer, setup script

**Manifest**:
A pinned list of what bootstrap installs: tools, PowerShell modules or ZSH plugins.
_Avoid_: lockfile, requirements

**Install plan**:
What the manifests ask for on one role, as a list of actions (an apt or winget package, the uv installer, a release binary, a uv tool, a plugin or module at its pin). Computed by `bootstrap/lib/plan.sh` or `Plan.ps1` from the files alone; it installs nothing.
_Avoid_: install list, resolved manifest

**Pins**:
Bringing a machine to every pin in its install plan and leaving what is already there alone (`bootstrap/lib/pins.sh`, `Sync-Pins.ps1`). Bootstrap runs it strictly (stop at the first failure); `update` runs it leniently (report, carry on).
_Avoid_: sync, reconcile step, upgrade

**Core tools**:
`shared/core-tools.txt`, the few core tools the profile leans on at startup (prompt, completions, `cd`, listing, git). Any one missing gives the single "run bootstrap" hint.
_Avoid_: required tools, hint list

**Local override**:
The per-machine file, kept outside the repo, holding values that differ on one machine, such as paths, a WSL distro or a token. Never committed; the repo ships only an `.example` of it.
_Avoid_: local config, env file

**Stub**:
The few-line file at a shell's own startup path (`$PROFILE`, `~/.zshrc`) that sources the profile from the repo clone.
_Avoid_: shim, wrapper

**conf.d**:
The numbered directory of small profile files (`core/conf.d`, `dev/conf.d`) that a shell's profile sources in one merged filename order. The same numbering on PowerShell and ZSH.
_Avoid_: profile.d, includes

**Parity list**:
`tests/parity.txt`, the single list of core command names and key behaviours (role gating, `EDITOR` defaults, missing-tool silence) that both the Pester and zsh suites read, so the four roles are checked against one definition of "feels the same".
_Avoid_: scenario copy, mirror tests

**Server MOTD**:
The `server-motd` login banner, installed by bootstrap and shown on Servers only. Nowhere's profile or the Linux `update-motd.d` hook is its single owner; its own `install-profile` and `uninstall-profile` are not used.
_Avoid_: banner script, motd profile

## Relationships

- A **role** is one of four; it decides which layers load (**core** always, **dev layer** on a DevBox only) and whether the **Server MOTD** shows.
- **Bootstrap** installs from a **manifest**, writes the **stub** and seeds the **local override**; the stub sets the role.
- The **install plan** is read from the **manifests** for a **role**; **pins** apply it, from bootstrap and from `update`.
- The **parity list** is how the shells are proven to agree on **core**.
