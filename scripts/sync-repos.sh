#!/bin/bash
# sync-repos - Keep all sibling repos on latest
# (every directory with a .git folder at the same level as this repo).
# This is what makes `workspace` the hub: run this before starting work
# anywhere else to ensure you're on the latest version of everything.
#
# Usage:
#   sync-repos.sh                    -> sync every repo (asks before each push/pull when interactive)
#   sync-repos.sh --check            -> fetch only, report behind/ahead/dirty, no pulls, no prompts
#   sync-repos.sh --non-interactive  -> no prompts: ff-pull clean behind-only repos, skip the rest
#   sync-repos.sh --yes              -> answer yes to safe pulls, still ask before pushes
#   sync-repos.sh <repo-name>        -> sync only that repo (e.g. sync-repos.sh bns)
#
# Safety rules:
#   1. NEVER touches repos with uncommitted changes (reports them, skips).
#   2. Only fast-forward pulls (never creates merge commits).
#   3. NEVER switches branches - acts on the branch you already have checked out.
#   4. NEVER pushes without an explicit yes (default answer is No).
#   5. NEVER resets, rebases, or rewrites history. Diverged repos are reported only.
#   6. No prompts when stdin is not a terminal or --non-interactive is given.

set -u
# Portable paths: repo root is the parent of this script's dir,
# sibling repos are the directories next to it. No absolute paths.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$REPO_DIR")"
CATALOGUE_FILE="$REPO_DIR/catalogue.txt"
CHECK_ONLY=0
NONINTERACTIVE=0
AUTOYES=0
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --non-interactive) NONINTERACTIVE=1 ;;
    --yes|-y) AUTOYES=1 ;;
    -h|--help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

# Prompts only when talking to a human. ai-sync --non-interactive, pipes,
# and CI all land here (no prompts, safe pulls only, pushes skipped).
INTERACTIVE=0
if [ "$NONINTERACTIVE" -eq 0 ] && [ "$CHECK_ONLY" -eq 0 ] && [ -t 0 ]; then
  INTERACTIVE=1
fi

# ask <prompt> <default: Y|N> -> return 0 on yes
# Non-interactive (no tty, or --non-interactive): safe pulls (default Y)
# proceed, pushes (default N) are skipped. --yes answers pulls without
# prompting in interactive mode; pushes always prompt when interactive.
ask() {
  local prompt="$1" default="$2" reply
  if [ "$INTERACTIVE" -eq 0 ]; then
    if [ "$default" = "Y" ]; then
      return 0
    fi
    return 1
  fi
  if [ "$AUTOYES" -eq 1 ] && [ "$default" = "Y" ]; then
    return 0
  fi
  if [ "$default" = "Y" ]; then
    read -r -p "$prompt [Y/n] " reply || return 1
    [[ "$reply" =~ ^([nN]|[nN][oO])$ ]] && return 1
    return 0
  else
    read -r -p "$prompt [y/N] " reply || return 1
    [[ "$reply" =~ ^([yY]|[yY][eE][sS])$ ]]
  fi
}

updated=0
pushed=0
up_to_date=0
skipped_dirty=0
skipped_declined=0
failed=0

# origin remote of a repo dir as owner/repo, or nothing on failure.
remote_name() {
  local url="$1"
  url=${url%.git}
  case "$url" in
    *@github.com:*) url=${url#*:} ;;
    *github.com/*) url=${url#*github.com/} ;;
    *) return 1 ;;
  esac
  echo "$url"
}

# Verify every catalogue.txt entry (owner/repo) is cloned next to this repo.
# Local directory names may differ from repo names; matching is by remote.
check_catalogue() {
  [ -f "$CATALOGUE_FILE" ] || return 0
  local present="" entry missing=0 d rn
  for d in "$PARENT_DIR"/*/; do
    [ -d "$d/.git" ] || continue
    rn=$(remote_name "$(git -C "$d" remote get-url origin 2>/dev/null)") || continue
    present="$present
$rn"
  done
  while IFS= read -r entry || [ -n "$entry" ]; do
    entry=$(printf '%s' "$entry" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$entry" ] && continue
    if ! printf '%s' "$present" | grep -qxF "$entry"; then
      echo "  CATALOGUE MISSING: $entry is not cloned next to this repo"
      missing=$((missing+1))
    fi
  done < "$CATALOGUE_FILE"
  if [ "$missing" -eq 0 ]; then
    echo "  catalogue: all entries present locally."
  fi
  return 0
}

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

  # sync mode (CHECK_ONLY=0)
  if [ "$dirty" -gt 0 ]; then
    echo "  $name [$branch]: SKIP - uncommitted changes ($dirty files). Commit/stash first."
    skipped_dirty=$((skipped_dirty+1))
    return
  fi
  if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
    echo "  $name [$branch]: DIVERGED (ahead $ahead, behind $behind) - needs manual rebase/merge, left alone."
    echo "    ${flags}"
    echo "    see: git -C \"$dir\" log --oneline --graph --left-right HEAD...@{u} | head"
    failed=$((failed+1))
    return
  fi
  if [ "$behind" -gt 0 ]; then
    # behind-only, clean: fast-forward pull is safe, but ask when interactive
    if ! ask "  $name [$branch]: pull $behind commit(s)?" Y; then
      echo "  $name [$branch]: declined (still behind by $behind)"
      skipped_declined=$((skipped_declined+1))
      return
    fi
    if git -C "$dir" pull --ff-only --quiet 2>&1 | head -n 5; then
      echo "  $name [$branch]: pulled ($behind commits)"
      updated=$((updated+1))
    else
      echo "  $name [$branch]: PULL FAILED (needs manual merge/rebase)"
      failed=$((failed+1))
    fi
    return
  fi
  if [ "$ahead" -gt 0 ]; then
    # ahead-only, clean: publishing - ask, default No, never in non-interactive
    upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "no-upstream")
    if ! ask "  $name [$branch]: push $ahead commit(s) to $upstream?" N; then
      echo "  $name [$branch]: not pushed (still ahead by $ahead)"
      skipped_declined=$((skipped_declined+1))
      return
    fi
    if git -C "$dir" push 2>&1 | tail -n 3; then
      echo "  $name [$branch]: pushed ($ahead commits)"
      pushed=$((pushed+1))
    else
      echo "  $name [$branch]: PUSH FAILED (check remote/permissions)"
      failed=$((failed+1))
    fi
    return
  fi
  echo "  $name [$branch]: up-to-date"
  up_to_date=$((up_to_date+1))
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

echo ""
echo "Catalogue check (minimum set from catalogue.txt):"
check_catalogue

if [ "$CHECK_ONLY" -eq 0 ]; then
  echo ""
  echo "Done: $updated pulled, $pushed pushed, $up_to_date up-to-date, $skipped_dirty skipped (dirty), $skipped_declined declined, $failed need-attention."
  echo "Tip: run with --check anytime to preview without pulling."
fi
