# CLAUDE.md

Nowhere is a personal shell environment: one setup that feels the same on four machine roles (`Windows DevBox/`, `Windows Server/`, `Linux DevBox/`, `Linux Server/`). Direction and open decisions live in the wayfinder map, GitHub issue #1; read it before planning work. The repo itself shows what exists so far.

Commits are guarded by gitleaks. Enable the hook once per clone: `git config core.hooksPath .githooks`.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (mookeyj79/Nowhere) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
