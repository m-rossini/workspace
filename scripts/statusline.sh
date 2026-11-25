#!/usr/bin/env bash
# Claude Code status line — directory, git branch/worktree, model, date/time,
# context + token usage, cost, session time, rate limits.
# Input: JSON on stdin (Claude Code statusLine contract). Output: 2 lines.
# Every field is optional: missing data is simply omitted, never an error.

input=$(cat)

# ---- colours (disabled when NO_COLOR is set) --------------------------------
if [ -z "${NO_COLOR:-}" ]; then
  R=$'\e[0m'; B=$'\e[1m'; DIM=$'\e[2m'
  CY=$'\e[36m'; GR=$'\e[32m'; YE=$'\e[33m'; RD=$'\e[31m'; MA=$'\e[35m'; BL=$'\e[34m'
else
  R=''; B=''; DIM=''; CY=''; GR=''; YE=''; RD=''; MA=''; BL=''
fi

j() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

# ---- human-friendly numbers: 950, 12.3k, 1.2M -------------------------------
fmt_num() {
  awk -v n="${1:-0}" 'BEGIN {
    if (n >= 1000000) printf "%.1fM", n/1000000;
    else if (n >= 1000) printf "%.1fk", n/1000;
    else printf "%d", n;
  }'
}

# ---- directory: show ~-relative path, keep the last two segments when long ---
cwd=$(j '.workspace.current_dir // .cwd')
[ -z "$cwd" ] && cwd=$PWD
dir_disp=${cwd/#$HOME/\~}
if [ "${#dir_disp}" -gt 40 ]; then
  dir_disp="…/$(basename "$(dirname "$cwd")")/$(basename "$cwd")"
  dir_disp=${dir_disp/#$HOME/\~}
fi

# ---- git: branch, dirty flag, ahead/behind, linked-worktree name ------------
git_seg=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_dir=$(git -C "$cwd" --no-optional-locks rev-parse --git-dir 2>/dev/null)
  common_dir=$(git -C "$cwd" --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null \
           || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

  dirty=""
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -n1)" ]; then
    dirty="${YE}*${R}"
  fi

  ab=""
  if upstream=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    read -r behind ahead < <(git -C "$cwd" --no-optional-locks rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)
    [ "${ahead:-0}" -gt 0 ] && ab+=" ${GR}↑${ahead}${R}"
    [ "${behind:-0}" -gt 0 ] && ab+=" ${RD}↓${behind}${R}"
  fi

  wt=""
  # Linked worktree: git-dir differs from the shared common dir.
  if [ -n "$git_dir" ] && [ -n "$common_dir" ] && \
     [ "$(cd "$cwd" && cd "$git_dir" && pwd -P)" != "$(cd "$cwd" && cd "$common_dir" && pwd -P)" ]; then
    wt_name=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
    wt=" ${MA}⎇ ${wt_name}${R}"
  fi

  git_seg="${BL}  ${branch}${R}${dirty}${ab}${wt}"
fi

# ---- model, date, time ------------------------------------------------------
model=$(j '.model.display_name // .model.id')
now_date=$(date '+%a %d %b %Y')
now_time=$(date '+%H:%M')

# ---- context window & tokens ------------------------------------------------
ctx_pct=$(j '.context_window.used_percentage')
ctx_size=$(j '.context_window.context_window_size')
tot_in=$(j '.context_window.total_input_tokens')
tot_out=$(j '.context_window.total_output_tokens')

ctx_seg=""
if [ -n "$ctx_pct" ]; then
  pct_int=$(printf '%.0f' "$ctx_pct")
  filled=$(( pct_int / 10 )); [ "$filled" -gt 10 ] && filled=10
  bar=""; for ((i=0;i<10;i++)); do [ "$i" -lt "$filled" ] && bar+="▰" || bar+="▱"; done
  if   [ "$pct_int" -ge 80 ]; then col=$RD
  elif [ "$pct_int" -ge 50 ]; then col=$YE
  else col=$GR; fi
  size_txt=""
  [ -n "$ctx_size" ] && size_txt=" $(fmt_num "$ctx_size")"
  ctx_seg="${col}${bar}${R} ${pct_int}%${DIM}${size_txt}${R}"
fi

tok_seg=""
if [ -n "$tot_in" ] || [ -n "$tot_out" ]; then
  tok_seg="${CY}↑$(fmt_num "${tot_in:-0}")${R} ${CY}↓$(fmt_num "${tot_out:-0}")${R} ${DIM}tok${R}"
fi

# ---- cost, session time, diff stats ----------------------------------------
cost=$(j '.cost.total_cost_usd')
cost_seg=""
[ -n "$cost" ] && cost_seg="$(printf '$%.2f' "$cost")"

dur_ms=$(j '.cost.total_duration_ms')
dur_seg=""
if [ -n "$dur_ms" ]; then
  s=$(( ${dur_ms%.*} / 1000 ))
  if   [ "$s" -ge 3600 ]; then dur_seg="$((s/3600))h$(( (s%3600)/60 ))m"
  elif [ "$s" -ge 60 ];   then dur_seg="$((s/60))m$((s%60))s"
  else dur_seg="${s}s"; fi
fi

add=$(j '.cost.total_lines_added'); del=$(j '.cost.total_lines_removed')
lines_seg=""
if [ -n "$add" ] || [ -n "$del" ]; then
  lines_seg="${GR}+${add:-0}${R}${DIM}/${R}${RD}-${del:-0}${R}"
fi

# ---- rate limits (subscription windows), when Claude Code provides them -----
rl_seg=""
rl5=$(j '.rate_limits.five_hour.used_percentage')
rl7=$(j '.rate_limits.seven_day.used_percentage')
[ -n "$rl5" ] && rl_seg+="5h ${DIM}$(printf '%.0f' "$rl5")%${R}"
[ -n "$rl7" ] && rl_seg+="${rl_seg:+ }7d ${DIM}$(printf '%.0f' "$rl7")%${R}"

# ---- assemble ----------------------------------------------------------------
SEP="${DIM} │ ${R}"
join() { # join non-empty segments with the separator
  local out="" s
  for s in "$@"; do
    [ -z "$s" ] && continue
    out="${out:+$out$SEP}$s"
  done
  printf '%s' "$out"
}

line1=$(join "${B}${CY}${dir_disp}${R}${git_seg}" "${MA}${model}${R}" "${DIM}${now_date} ${R}${B}${now_time}${R}")
line2=$(join "$ctx_seg" "$tok_seg" "${YE}${cost_seg}${R}" "${dur_seg:+⏱ $dur_seg}" "$lines_seg" "$rl_seg")

printf '%s\n' "$line1"
[ -n "$line2" ] && printf '%s\n' "$line2"
exit 0
