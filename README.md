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
./scripts/sync-repos.sh           # pull every clean repo (ff-only, skips dirty)

# Single repo
./scripts/sync-repos.sh bns

# Full hub sync (skills + MCP collect + MCP distribute + repos)
./ai-sync --non-interactive
./ai-sync                         # interactive menu
```

### Safety rules (`sync-repos.sh`)

1. Never touches repos with uncommitted changes — reports and skips them.
2. Only `git pull --ff-only` — never creates merge commits.
3. Never switches branches — pulls whatever is checked out.
4. Never pushes, deletes, or rewrites history.

## Sibling repos covered

Discovered dynamically: every directory under `/home/perez/projetos/` with a
`.git` folder. Current set (Nov 2026): `OneGoodArea`, `bns`, `document_repo`,
`dotfiles`, `international_futebol_data`, `international_results`, `mroffice`,
`photo_pipeline`, `spotdata`, `sysdyn`, `toejam_and_earl`, plus `workspace` itself.
Non-git folders (`balance`, `config`, `data`, `tv`, …) are skipped.

Known caveat: `photo_pipeline` uses an `https://` remote and its `fetch` fails
without terminal auth — switch it to SSH (`git@github.com:…`) or `gh auth login`
to include it in automated syncs.

## Git conventions (see `skills/git/SKILL.md`)

- Default branch (`main`/`master`) is never edited directly.
- Work on feature branches, commit there, open PRs with `gh`.
- Confirm before push / PR merge / destructive steps.
