# CLAUDE.md — workspace (hub)

Claude Code loads this file automatically. The same rules are in
[AGENTS.md](AGENTS.md) for Codex and OpenCode; keep the two in sync.

@AGENT.md
@README.md

## Claude-specific notes

- The status line is configured in `~/.claude/settings.json` (`statusLine`) and
  runs `~/.claude/statusline.sh`, which symlinks to `scripts/statusline.sh`.
  Edit `scripts/statusline.sh` in this repo; the `$HOME` path is only a link.
- Use `/clear` or `/compact` when the context-window bar in the status line
  turns red (80%+) on long sessions.
