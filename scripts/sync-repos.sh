#!/bin/bash
# sync-repos - Keep all sibling repos under /home/perez/projetos on latest
# This is what makes `workspace` the hub: run this before starting work
# anywhere else to ensure you're on the latest version of everything.
#
# Usage:
#   sync-repos.sh              -> fetch + fast-forward pull every clean repo
#   sync-repos.sh --check      -> fetch only, report behind/ahead/dirty, no pulls
#   sync-repos.sh <repo-name>  -> sync only that repo (e.g. sync-repos.sh bns)
#
# Safety rules:
#   1. NEVER touches repos with uncommitted changes (reports them, skips pull).
#   2. Only fast-forward pulls (never creates merge commits).
#   3. NEVER switches branches - pulls the branch you already have checked out.
#   4. NEVER pushes, deletes, or rewrites history.

set -u
PARENT_DIR="/home/perez/projetos"
CHECK_ONLY=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

updated=0
up_to_date=0
skipped_dirty=0
failed=0

sync_one() {
  local dir="$1"
  local name
  name=$(basename "$dir")
  local branch dirty behind ahead

  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
    echo "  $name: ERROR (not a git repo?)"
    failed=$((failed+1))
    return
  }
  local fetch_out
  fetch_out=$(git -C "$dir" fetch --prune 2>&1) || {
    echo "  $name [$branch]: FETCH FAILED - ${fetch_out:-check remote/auth} (showing last known state)"
  }

  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l)
  # ahead/behind vs upstream, if tracking exists
  behind=0; ahead=0
  if git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    behind=$(git -C "$dir" rev-list --count HEAD..'@{u}' 2>/dev/null || echo 0)
    ahead=$(git -C "$dir" rev-list --count '@{u}'..HEAD 2>/dev/null || echo 0)
  fi

  local flags=""
  [ "$dirty" -gt 0 ] && flags="${flags} dirty($dirty)"
  [ "$behind" -gt 0 ] && flags="${flags} behind($behind)"
  [ "$ahead" -gt 0 ] && flags="${flags} ahead($ahead)"

  if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ "$dirty" -gt 0 ]; then
      echo "  $name [$branch]: DIRTY - commit/stash before pulling$flags"
    elif [ "$behind" -gt 0 ]; then
      echo "  $name [$branch]: BEHIND by $behind (would pull)$flags"
    elif [ "$ahead" -gt 0 ]; then
      echo "  $name [$branch]: AHEAD by $ahead (nothing to pull)$flags"
    else
      echo "  $name [$branch]: up-to-date$flags"
    fi
    return
  fi

  # pull mode
  if [ "$dirty" -gt 0 ]; then
    echo "  $name [$branch]: SKIP - uncommitted changes ($dirty files). Commit/stash first."
    skipped_dirty=$((skipped_dirty+1))
    return
  fi
  if [ "$behind" -eq 0 ]; then
    echo "  $name [$branch]: up-to-date"
    up_to_date=$((up_to_date+1))
    return
  fi
  if git -C "$dir" pull --ff-only --quiet 2>&1 | head -n 5; then
    echo "  $name [$branch]: pulled ($behind commits)"
    updated=$((updated+1))
  else
    echo "  $name [$branch]: PULL FAILED (needs manual merge/rebase)"
    failed=$((failed+1))
  fi
}

echo "Syncing sibling repos in $PARENT_DIR ..."
if [ -n "$TARGET" ]; then
  if [ -d "$PARENT_DIR/$TARGET/.git" ]; then
    sync_one "$PARENT_DIR/$TARGET"
  else
    echo "Error: '$TARGET' is not a git repo under $PARENT_DIR"
    exit 1
  fi
else
  for d in "$PARENT_DIR"/*/; do
    [ -d "$d/.git" ] || continue
    # Don't sync ourselves mid-run in pull mode weirdness - include, it's safe
    sync_one "$d"
  done
fi

if [ "$CHECK_ONLY" -eq 0 ]; then
  echo ""
  echo "Done: $updated pulled, $up_to_date up-to-date, $skipped_dirty skipped (dirty), $failed failed."
  echo "Tip: run with --check anytime to preview without pulling."
fi
