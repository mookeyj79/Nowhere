# CLAUDE.md

The design is decided and built. Before changing a design decision, read why it was made in the closed wayfinder map (GitHub issue #1, its comments and linked tickets). `README.md` covers layout, bootstrap and tests.

- Keep PowerShell and ZSH command names and behaviour identical; a change to a core command goes into `tests/parity.txt` too.
- Install through bootstrap (`bootstrap/bootstrap.ps1` or `bootstrap.sh <devbox|server>`); it also enables the gitleaks commit hook. On a clone that wasn't bootstrapped, run `git config core.hooksPath .githooks`.
- On Windows, run the zsh tests through WSL: `wsl -d Debian --cd <clone as /mnt/<drive>/...> -- bash tests/zsh/run.sh [scenario-id ...]`, from PowerShell (Git Bash rewrites `/mnt/...` paths; there, prefix `MSYS_NO_PATHCONV=1`). Pester takes several minutes; run it last.
- Run Python through `uv` (`uv run`, `uvx`, `uv add`); bootstrap installs it on every role.
- Change the map body only through `scripts/map-append.sh` or `gh issue comment 1`.

## Agent skills

- Issue tracker: GitHub Issues (mookeyj79/Nowhere) via `gh`. See `docs/agents/issue-tracker.md`.
- Triage labels: see `docs/agents/triage-labels.md`.
- Domain docs: single-context, `GLOSSARY.md` and `docs/adr/` at the root. See `docs/agents/domain.md`.
