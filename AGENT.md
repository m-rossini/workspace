# workspace — hub instructions

This repo (`/home/perez/projetos/workspace`) is the **main project / hub** for all
repos under `/home/perez/projetos/`. Product code lives in the siblings; shared
agent config and sync tooling live here.

## Sources of truth

- Skills: `skills/` in this repo (canonical). `skills/synced/` is a generated
  cache — never edit it, never treat it as source.
- MCP servers: `mcp/servers.json` in this repo (canonical).
- Agent machines (`~/.claude/skills/`, `~/.codex/skills/`, `~/.config/opencode/…`)
  are *targets*, synced from here via `scripts/sync-skills.sh` and
  `scripts/sync-mcp-distribute.py` (add-only, never overwrites existing entries).

## Keep-everything-on-latest

- Before starting work in any sibling repo, run `./scripts/sync-repos.sh --check`
  (preview) then `./scripts/sync-repos.sh` (fetch + `pull --ff-only` on clean repos).
- The script never touches dirty repos, never switches branches, never merges
  non-fast-forward, never pushes. Dirty/behind repos are reported for manual handling.
- `./ai-sync` (interactive) or `./ai-sync --non-interactive` runs the full hub
  sync: skills + MCP collect + MCP distribute + repos.

## Skill trigger guide

You have access to local skills (symlinked from this repo). Use this guide to
determine when to trigger them contextually:

## 1. Multi-Agent Synchronization (`agent-coordination`)
- **Path:** `skills/agent-coordination/`
- **When to trigger:** Use when working in a repository where multiple AI CLI agents (Claude, Codex, Gemini, etc.) are working concurrently in separate Git worktrees.
- **Behavior:** Check for `COLLABORATION.md` at the project root, use it as an ephemeral scratchpad, prune resolved entries, and record permanent architectural decisions in Jira if available. Ignore if working alone.

## 2. Concise Writing (`concise-writing`)
- **Path:** `skills/concise-writing/`
- **When to trigger:** Use when the user requests direct, punchy, low-fluff answers, status reports, or summaries without conversational filler.

## 3. Container Testing (`container-test`)
- **Path:** `skills/container-test/`
- **When to trigger:** Use when setting up, running, or debugging containerized environments (Docker/Podman) or executing test suites.

## 4. Git Workflows (`git`)
- **Path:** `skills/git/`
- **When to trigger:** Use when managing complex git operations, branch strategies, worktrees, or resolving merge states.
- **Hub rule:** per that skill, never edit/commit directly to a default branch; confirm before push, PR merge, or destructive steps. This applies to `workspace` and every sibling.
