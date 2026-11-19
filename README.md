# workspace — hub for all projects

`workspace` is the **main project**. It does not hold product code. It holds the
shared config every other repo relies on, plus the scripts that keep all sibling
repos under `/home/perez/projetos/` on the latest version.

## What lives here

| Path | Role |
|---|---|
| `skills/` | Source of truth for agent skills (`agent-coordination`, `git`, `container-test`, `concise-writing`, …). `skills/synced/` is a generated cache, git-ignored. |
| `mcp/servers.json` | Source of truth for MCP server definitions. |
| `scripts/sync-skills.sh` | Links skills into Claude / Codex / OpenCode. |
| `scripts/sync-mcp-collect.py` | Pulls MCP definitions from all agent configs into `mcp/servers.json`. |
| `scripts/sync-mcp-distribute.py` | Adds missing MCP servers to all agent configs (add-only, never overwrites). |
| `scripts/sync-mcp-remove.py <name>` | Removes an MCP server from `servers.json` + all agent configs. |
| `scripts/sync-repos.sh` | Fetches + fast-forward-pulls every sibling git repo. This is the "always on latest" mechanism. |
| `ai-sync` | Interactive driver (and `--non-interactive` full-sync) over all of the above. |

## Workflows

```bash
# Before starting work anywhere: bring everything to latest
./scripts/sync-repos.sh --check   # preview: behind / ahead / dirty per repo
./scripts/sync-repos.sh           # interactive: asks before each pull/push

# Unattended (e.g. from ai-sync): safe pulls only, pushes skipped, no prompts
./scripts/sync-repos.sh --non-interactive
./scripts/sync-repos.sh --yes     # answer yes to safe pulls, still ask before pushes

# Single repo
./scripts/sync-repos.sh bns
```

### Safety rules (`sync-repos.sh`)

1. Never touches repos with uncommitted changes — reports and skips them.
2. Only `git pull --ff-only` — never creates merge commits.
3. Never switches branches — acts on whatever is checked out.
4. Pushes only on an explicit yes (default answer is No; never in
   `--non-interactive` mode). Ahead-only repos are reported, not published.
5. Never resets, rebases, or rewrites history. Diverged repos are reported
   with a log command for manual resolution.
6. No prompts when stdin is not a terminal or `--non-interactive` is given —
   safe pulls proceed, everything else is skipped and counted.

## Sibling repos covered

Discovered dynamically: every directory under `/home/perez/projetos/` with a
`.git` folder. Current set (Nov 2026): `OneGoodArea`, `bns`, `document_repo`,
`dotfiles`, `international_futebol_data`, `international_results`, `mroffice`,
`photo_pipeline`, `spotdata`, `sysdyn`, `toejam_and_earl`, plus `workspace` itself.
Non-git folders (`balance`, `config`, `data`, `tv`, …) are skipped.

Remotes should use SSH (`git@github.com:…`) so `fetch` works non-interactively;
`photo_pipeline` was previously `https://` and has been switched to SSH.

## Git conventions (see `skills/git/SKILL.md`)

- Default branch (`main`/`master`) is never edited directly.
- Work on feature branches, commit there, open PRs with `gh`.
- Confirm before push / PR merge / destructive steps.
