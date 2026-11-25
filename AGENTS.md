# AGENTS.md — workspace (hub)

This file is read natively by **Codex** and **OpenCode**. Claude Code reads
[CLAUDE.md](CLAUDE.md), which imports the same hub docs.

Before doing anything, read both:

1. [AGENT.md](AGENT.md) — hub rules, command map, MCP list, skill triggers.
2. [README.md](README.md) — repo layout, sync workflows, safety rules.

## Ground rules (all agents)

- This repo is the **hub**: shared agent config and sync tooling. Product code
  lives in the sibling directories (each one with its own `.git`).
- **Never edit or commit directly on `main`.** Branch first (`feat/…`, `fix/…`,
  `docs/…`), and confirm before push, PR merge, or any destructive step.
- **No absolute local paths** in committed files. Derive the repo root from the
  file's own location (`scripts/…` resolves from `$(dirname "$0")`).
- Canonical sources: `skills/` (not `skills/synced/`, which is a generated
  cache) and `mcp/servers.json`. Agent-machine configs are *targets*.
- Prefer MCP servers over skills for live data or actions; skills cover workflow.
- Before working in any sibling repo, check it is current:
  `./scripts/sync-repos.sh --check`, then `./scripts/sync-repos.sh` if needed.

## Status line (Claude Code + OpenCode)

- Source of truth for Claude Code: `scripts/statusline.sh` (committed).
- Claude Code runs it via `~/.claude/statusline.sh`, a symlink to that file,
  and `statusLine` in `~/.claude/settings.json`.
- OpenCode runs `@rashidrazak/opencode-status-line` (v1.2.0) via `plugins` in
  `~/.config/opencode/cli.json`, alongside the local `plugins/hostname` plugin.
  Config file (optional): `~/.config/opencode/opencode-status-line.json`.
- It shows: directory, git branch, dirty/ahead/behind markers, linked-worktree
  name, model, date and time, context bar, input/output tokens, cost, session
  time, line diff, and 5h/7d rate limits when available.
- To change it: edit `scripts/statusline.sh`, then test with sample JSON:
  `echo '{"model":{"display_name":"X"}}' | NO_COLOR=1 bash scripts/statusline.sh`.
  Keep it dependency-light (bash, `jq`, `git`, `awk`) and never fail on missing fields.

## Working style

- Make the smallest change that answers the request; state the reading you took
  when a request is ambiguous.
- Verify with the repo's own scripts where they exist (`--check` modes first).
- Report results plainly: what ran, what passed, what was skipped.
