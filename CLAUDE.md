# CLAUDE.md

Before planning work, read the wayfinder map (GitHub issue #1 and its comments): direction and decisions live there. `README.md` covers layout, bootstrap and tests.

- Keep PowerShell and ZSH command names and behaviour identical; a change to a core command goes into `tests/parity.txt` too.
- Install through bootstrap (`bootstrap/bootstrap.ps1` or `bootstrap.sh <devbox|server>`); it also enables the gitleaks commit hook. On a clone that wasn't bootstrapped, run `git config core.hooksPath .githooks`.
- On Windows, run the zsh tests through WSL: `wsl -d Debian --cd <path> -- bash tests/zsh/run.sh [scenario-id ...]`. Pester takes several minutes; run it last.
- Run Python through `uv` (`uv run`, `uvx`, `uv add`); bootstrap installs it on every role.
- Change the map body only through `scripts/map-append.sh` or `gh issue comment 1`.

## Agent skills

- Issue tracker: GitHub Issues (mookeyj79/Nowhere) via `gh`. See `docs/agents/issue-tracker.md`.
- Triage labels: see `docs/agents/triage-labels.md`.
- Domain docs: single-context, `GLOSSARY.md` and `docs/adr/` at the root. See `docs/agents/domain.md`.
