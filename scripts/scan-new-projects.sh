#!/bin/bash
# scan-new-projects - Find sibling directories that are not git repos yet and
# ask whether to add them to the hub (git init + initial commit, optionally
# a private GitHub repo + push).
#
# Usage:
#   scan-new-projects.sh                  -> interactive: walk every untracked dir
#   scan-new-projects.sh --check          -> report only, no prompts, no changes
#   scan-new-projects.sh --non-interactive -> same as --check (never inits)
#   scan-new-projects.sh --yes            -> answer safe inits without prompting,
#                                            still asks before GitHub create/push
#   scan-new-projects.sh <name>           -> only that directory
#
# Safety rules (same spirit as sync-repos.sh):
#   1. Portable paths: repo root is the parent of this script's dir.
#      Sibling projects are the directories next to it. No absolute paths.
#   2. Directories listed in .sync-ignore (repo root) are never suggested.
#   3. Large directories (>1GB) are reported, never auto-initialized.
#   4. GitHub repo creation + push only on an explicit yes (default No,
#      never in non-interactive mode). Uses `gh` when available.
#   5. No prompts when stdin is not a terminal or --non-interactive is given.
#   6. Windows ADS junk (*:Zone.Identifier) is git-ignored by default.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$REPO_DIR")"
IGNORE_FILE="$REPO_DIR/.sync-ignore"

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
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

INTERACTIVE=0
if [ "$NONINTERACTIVE" -eq 0 ] && [ "$CHECK_ONLY" -eq 0 ] && [ -t 0 ]; then
  INTERACTIVE=1
fi

# ask <prompt> <default: Y|N> -> return 0 on yes
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

is_ignored() {
  local name="$1"
  [ -f "$IGNORE_FILE" ] || return 1
  grep -qxE "[[:space:]]*$name[[:space:]]*" "$IGNORE_FILE" 2>/dev/null
}

remember_ignore() {
  local name="$1"
  if grep -q "^$name$" "$IGNORE_FILE" 2>/dev/null; then
    return 0
  fi
  echo "$name" >> "$IGNORE_FILE"
  echo "  added '$name' to .sync-ignore"
}

added=0
skipped=0
ignored_count=0

scan_one() {
  local dir="$1"
  local name
  name=$(basename "$dir")
  local size files

  size=$(du -sh "$dir" 2>/dev/null | cut -f1)
  files=$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l)

  if [ "$files" -eq 0 ]; then
    echo "  $name: EMPTY dir ($size) - not a repo yet"
  else
    echo "  $name: $files top-level entr(ies), $size - not a repo yet"
    if [ "$CHECK_ONLY" -eq 1 ]; then
      ls -A "$dir" | head -5 | sed 's/^/    /'
    fi
    return 0
  fi
}

add_one() {
  local dir="$1"
  local name
  name=$(basename "$dir")
  local size files

  size=$(du -sh "$dir" 2>/dev/null | cut -f1)
  files=$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l)

  echo "  $name ($size, $files top-level entries):"
  ls -A "$dir" | head -8 | sed 's/^/    /'

  # Large dirs: report, offer ignore, never init unprompted.
  if [ "$(du -sm "$dir" 2>/dev/null | cut -f1)" -gt 1024 ]; then
    echo "  $name is larger than 1GB - not auto-initializing."
    if ask "  Add '$name' to .sync-ignore so it is never suggested?" N; then
      remember_ignore "$name"
    fi
    skipped=$((skipped+1))
    return
  fi

  if ! ask "  git init '$name' with an initial commit?" N; then
    if ask "  Never suggest '$name' again (add to .sync-ignore)?" N; then
      remember_ignore "$name"
    else
      skipped=$((skipped+1))
    fi
    return
  fi

  if [ "$files" -eq 0 ]; then
    printf '# %s\n\nEmpty for now.\n' "$name" > "$dir/README.md"
    echo "  placeholder README.md created (empty dirs cannot be committed)"
  fi
  printf '*:Zone.Identifier\n' > "$dir/.gitignore"

  git -C "$dir" init -b main --quiet || { echo "  git init FAILED"; skipped=$((skipped+1)); return; }
  git -C "$dir" add -A
  if ! git -C "$dir" commit -m "Initial commit" --quiet 2>&1 | head -3; then
    echo "  commit FAILED"
    skipped=$((skipped+1))
    return
  fi
  echo "  initialized with initial commit: $(git -C "$dir" rev-parse --short HEAD)"
  added=$((added+1))

  if ! ask "  Create private GitHub repo and push '$name'?" N; then
    echo "  left local-only (push later with: git remote add origin <url> && git push -u origin main)"
    return
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "  'gh' not installed - create the repo manually, then:"
    echo "    git -C \"$dir\" remote add origin git@github.com:<owner>/$name.git"
    echo "    git -C \"$dir\" push -u origin main"
    return
  fi
  if gh repo create "$name" --private --source "$dir" --push 2>&1 | tail -3; then
    echo "  pushed to GitHub"
  else
    echo "  GitHub create/push FAILED - repo stays local-only"
  fi
}

echo "Scanning for new (non-git) projects next to $PARENT_DIR ..."
echo "(ignored via .sync-ignore: $([ -f "$IGNORE_FILE" ] && grep -cv '^[[:space:]]*#' "$IGNORE_FILE" | tr -d ' ' || echo 0))"

if [ -n "$TARGET" ]; then
  if [ -d "$PARENT_DIR/$TARGET/.git" ]; then
    echo "Error: '$TARGET' is already a git repo."
    exit 1
  elif [ -d "$PARENT_DIR/$TARGET" ]; then
    if [ "$CHECK_ONLY" -eq 1 ]; then
      scan_one "$PARENT_DIR/$TARGET"
    else
      add_one "$PARENT_DIR/$TARGET"
    fi
  else
    echo "Error: '$TARGET' is not a directory next to this repo."
    exit 1
  fi
else
  found=0
  for d in "$PARENT_DIR"/*/; do
    [ -d "$d/.git" ] && continue
    name=$(basename "$d")
    if is_ignored "$name"; then
      ignored_count=$((ignored_count+1))
      continue
    fi
    found=$((found+1))
    if [ "$CHECK_ONLY" -eq 1 ] || [ "$INTERACTIVE" -eq 0 ]; then
      scan_one "$d"
    else
      add_one "$d"
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "  nothing new ($ignored_count ignored)."
  fi
fi

if [ "$CHECK_ONLY" -eq 0 ]; then
  echo ""
  echo "Done: $added initialized, $skipped skipped."
  echo "Tip: run with --check anytime to preview without prompting."
fi
