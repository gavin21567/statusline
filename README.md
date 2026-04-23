# Claude Code Status Line

A three-line status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with health-aware rate-limit bars and a consolidated four-role color palette.

## Preview

```
Apr 23 15:11 | statusline (HEAD) | +42 -17 | Opus 4.7 [medium] | 72% ctx | $1.23
5hr  ▰▰▰▰▰▱▱▱▱▱▱  45%   Nov 21, 1:46am
7day ▰▰▰▱▱▱▱▱▱▱▱  23%   Nov 21, 1:46am
```

- **Line 1**: date/time · dir (branch) · +lines -lines · model [effort] · ctx% · $cost
- **Line 2**: 5-hour rate-limit bar with reset time
- **Line 3**: 7-day rate-limit bar with reset time

All segments are conditionally displayed — they only appear when data is available.

## Color palette (four semantic roles)

| Role | Purpose | Color |
|---|---|---|
| Accent | Health / warnings (rate bars, ctx%) | mint `78` → gold `221` → coral `203` |
| Focus | Model name (needs attention) | lavender `183` |
| Identity | Stable labels (dir, cost, date, etc.) | warm tan `180` |
| Neutral | Secondary info (dimmed via `\033[2m`) | — |

Rate bars turn **gold at ≥70%** and **coral at ≥90%**. Context color reverses: coral at **<20%** remaining, gold at **<50%**.

## Installation

1. Copy the script to your Claude config directory:

```bash
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

2. Add the following to `~/.claude/settings.json`:

```json
{
  "statusLine": "cat | bash ~/.claude/statusline-command.sh"
}
```

3. Restart Claude Code.

## Requirements

- `jq` — for parsing the JSON payload from Claude Code
- `git` — for branch detection
- `bash` 4+ — for parameter expansion features

## Customization

All colors are defined as `C_*` variables at the top of the script using ANSI 256-color codes. Health thresholds (`PCT_WARN`, `PCT_CRIT`, `CTX_WARN`, `CTX_CRIT`) and bar width (`BAR_WIDTH`) are `readonly` constants right above the palette.

## License

MIT
