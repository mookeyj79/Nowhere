# CLAUDE.md

Nowhere is a personal shell environment: one setup that feels the same on four machine roles (Windows DevBox, Windows Server, Linux DevBox, Linux Server). Direction and decisions live in the wayfinder map, GitHub issue #1 and its comments; read it before planning work. `README.md` describes the built layout.

## Layout

Files are organised by shell: `shared/` (starship.toml, tool manifest), `powershell/` and `zsh/` (each: profile entry point, `core/` + `dev/` with numbered `conf.d/` and `bin/`, pinned module or plugin manifest, `local.*.example`), `bootstrap/` (`bootstrap.ps1`, `bootstrap.sh`), `tests/`. Core loads on every role; the dev layer only when `NOWHERE_ROLE=devbox`. Keep PowerShell and ZSH command names identical: a change to a core command name or behaviour goes into `tests/parity.txt` too.

## Commands

- Bootstrap a machine: `bootstrap/bootstrap.ps1 <devbox|server>` or `bootstrap/bootstrap.sh <devbox|server>` (idempotent). Do not hand-install; bootstrap also enables the commit hook.
- zsh tests: `bash tests/zsh/run.sh [scenario-id ...]` (needs zsh, jq; on Windows via `wsl -d Debian --cd <path> -- bash tests/zsh/run.sh`).
- Pester: `Invoke-Pester tests/powershell` (slow, several minutes).
- Never edit the map body by hand; use `scripts/map-append.sh` or `gh issue comment 1`.

Commits are guarded by gitleaks. On a clone that was not bootstrapped, enable the hook with `git config core.hooksPath .githooks`.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (mookeyj79/Nowhere) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
