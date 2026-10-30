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

**Local override**:
The per-machine file, kept outside the repo, holding values that differ on one machine, such as paths, a WSL distro or a token. Never committed; the repo ships only an `.example` of it.
_Avoid_: local config, env file

**Stub**:
The few-line file at a shell's own startup path (`$PROFILE`, `~/.zshrc`) that sources the profile from the repo clone.
_Avoid_: shim, wrapper
