---
name: git
description: Use for git work — branching, worktrees, commit, push, pull requests, merge, and cleanup. Keeps the default branch untouched by working on feature branches or worktrees.
---

# Git Workflow

## Principles

1. Never edit neither commit directly to the default branch (`main`, or `master` if that is what the repo uses). Do not rename an existing default branch.
2. Work on a new branch per task. For large or parallel work, suggest a worktree and let the user choose. Again, never change file sin main, that is BIG RED LINE. If there is any indication of Jira in the plan, prefix the branch name with the Jira key (e.g. `AR-123-short-desc`).
3. Confirm with the user before outward-facing or destructive steps: push, opening/merging a PR, deleting branches, discarding changes. In general, never perform destructive actions without explicit confirmation: force pushes, hard resets, deleting branches, deleting files, overwriting user work.
4. Use the `gh` CLI for PRs. If it is unavailable, use the GitHub MCP tools.

## Workflow

1. **Setup**: if not a repo and the user wants one, always create it with `main` as the default branch (`git init -b main`, never `master`). Check `git status` and the current branch first.
2. **Branch**: `git checkout -b <branch>`, or `git worktree add ../<dir> -b <branch>` for large work.
3. **Commit**: every logical change gets its own commit — keep commits small, incremental, and reviewable, never bundle unrelated changes. Stage specific files (`git add <file>`), review with `git diff --staged`, then `git commit -m "<message>"` with a message that describes intent (prefer `Add validation for missing workspace config`, avoid `fix stuff`). Avoid `git add -A` unless every change is intended.
4. **Push**: `git push -u origin <branch>` (after confirmation).
5. **PR**: `gh pr create`, using the repo's PR template if present.
6. **Merge**: merge the PR (`gh pr merge`) rather than merging locally into the default branch.
7. **Update main**: `git checkout <default> && git pull`.
8. **Cleanup** (only when the user asks): `git worktree remove <path>`, `git branch -d <branch>`. Use `-D` or `--force` only after the user confirms unmerged work can be lost.

## Full finish

"Full finish" means steps 3-7 above, in order: commit the work, push the
branch, open a PR, merge the PR, then update the local default branch.
Pause for confirmation at push and at merge. Never skip the PR + merge on
shared repos to "save time" — that is what full-finish forbids.

## Useful commands

- `git branch` / `git branch -a`: list branches
- `git worktree list`: list worktrees
- `git log --oneline -n 10`: recent history
- `git status`, `git diff`: inspect state
