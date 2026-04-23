#!/bin/bash
# Claude Code Status Line — 3 colored lines.
#   1: time · dir (branch) · +lines -lines · model [effort] · ctx · $cost
#   2: 5hr  ▰▰▰▱░░░░░░░ 45%   reset-time
#   3: 7day ▰▰░░░░░░░░░ 23%   reset-time

readonly BAR_WIDTH=11
readonly PCT_WARN=70       # bar turns gold at this used% threshold
readonly PCT_CRIT=90       # bar turns coral red
readonly CTX_WARN=50       # ctx% turns gold when remaining below
readonly CTX_CRIT=20       # ctx% turns coral red when remaining below

# Palette — four semantic roles (accent / focus / identity / neutral)
C_ACCENT_OK='\033[38;5;78m'    # Healthy: mint green
C_ACCENT_WARN='\033[38;5;221m' # Warning: warm gold
C_ACCENT_CRIT='\033[38;5;203m' # Critical: coral red
C_FOCUS='\033[38;5;183m'       # Focus (model): cool lavender
C_DIFF_ADD='\033[38;5;114m'    # Diff added: sage green
C_DIFF_DEL='\033[38;5;174m'    # Diff removed: dusty rose
C_IDENTITY='\033[38;5;180m'    # Stable labels: warm tan
C_BAR_EMPTY='\033[38;5;238m'   # Bar empty track: deep gray
C_WHITE='\033[38;5;255m'       # Rate label + reset time
DIM='\033[2m'
RESET='\033[0m'

input=$(cat)

# Single jq extracts every field, one per line. Line-delimited avoids the
# IFS-tab pitfall where consecutive tabs (empty fields) collapse into one.
{
    IFS= read -r current_dir
    IFS= read -r model_raw
    IFS= read -r remaining
    IFS= read -r transcript_path
    IFS= read -r five_hr_pct
    IFS= read -r five_hr_reset
    IFS= read -r seven_day_pct
    IFS= read -r seven_day_reset
    IFS= read -r lines_added
    IFS= read -r lines_removed
    IFS= read -r session_cost
} < <(jq -r '
    .workspace.current_dir,
    .model.display_name,
    (.context_window.remaining_percentage // ""),
    (.transcript_path // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.cost.total_cost_usd // "")' <<<"$input")

model=${model_raw% (*}
dir_name=${current_dir##*/}
git_branch=$(git -C "$current_dir" -c core.fileMode=false rev-parse --abbrev-ref HEAD 2>/dev/null)

# tail -c bounds transcript scan — effort-change log lines are always recent.
effort=""
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    effort=$(tail -c 65536 "$transcript_path" 2>/dev/null | grep -o 'Set effort level to [a-z]*:' | tail -1 | sed 's/.*to //;s/://')
fi
if [ -z "$effort" ]; then
    effort=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)
fi
effort=${effort:-high}

# One date fork yields all three time fields.
now_info=$(date "+%b %d|%H:%M|%s")
current_date=${now_info%%|*}; now_info=${now_info#*|}
current_time=${now_info%|*}
now_epoch=${now_info##*|}

# Renders one rate-limit row (label · bar · pct · optional reset time) directly
# to stdout. Health color applies to bar fill and percentage; empty track and
# reset time keep their own neutrals. Silent when pct is empty/null.
#   cell mapping: 0%→0, 1-9%→1, 10-19%→2, ..., 90-99%→10, 100%+→11
render_rate_line() {
    local label=$1 pct_raw=$2 reset=$3
    [ -z "$pct_raw" ] || [ "$pct_raw" = "null" ] && return
    local pct pct_fmt color filled f="" e="" i reset_str=""
    printf -v pct "%.0f" "$pct_raw"

    if   [ "$pct" -ge "$PCT_CRIT" ]; then color=$C_ACCENT_CRIT
    elif [ "$pct" -ge "$PCT_WARN" ]; then color=$C_ACCENT_WARN
    else                                  color=$C_ACCENT_OK
    fi

    if   [ "$pct" -le 0 ];   then filled=0
    elif [ "$pct" -ge 100 ]; then filled=$BAR_WIDTH
    else                          filled=$((pct / 10 + 1))
    fi
    for ((i=0; i<filled; i++)); do f+="▰"; done
    for ((i=filled; i<BAR_WIDTH; i++)); do e+="▱"; done

    printf -v pct_fmt '%3d%%' "$pct"

    if [ -n "$reset" ] && [ "$reset" != "null" ] && [ "$reset" -gt "$now_epoch" ] 2>/dev/null; then
        local t
        t=$(date -r "$reset" "+%b %e, %l:%M%p" 2>/dev/null)
        t=${t//AM/am}; t=${t//PM/pm}
        while [[ $t == *"  "* ]]; do t=${t//  / }; done
        reset_str="   ${C_WHITE}${t}${RESET}"
    fi

    printf '%b%-4s%b %b%s%b%s%b %b%s%b%b' \
        "$C_WHITE" "$label" "$RESET" \
        "$color" "$f" "$C_BAR_EMPTY" "$e" "$RESET" \
        "$color" "$pct_fmt" "$RESET" \
        "$reset_str"
}

output="${C_IDENTITY}${current_date} ${current_time}${RESET}"

if [ -n "$git_branch" ]; then
    output="${output} ${DIM}|${RESET} ${C_IDENTITY}${dir_name}${RESET} ${DIM}${C_IDENTITY}(${git_branch})${RESET}"
else
    output="${output} ${DIM}|${RESET} ${C_IDENTITY}${dir_name}${RESET}"
fi

if [ "$lines_added" != "0" ] || [ "$lines_removed" != "0" ]; then
    output="${output} ${DIM}|${RESET} ${C_DIFF_ADD}+${lines_added}${RESET} ${C_DIFF_DEL}-${lines_removed}${RESET}"
fi

output="${output} ${DIM}|${RESET} ${C_FOCUS}${model}${RESET} ${DIM}${C_FOCUS}[${effort}]${RESET}"

if [ -n "$remaining" ] && [ "$remaining" != "null" ]; then
    printf -v remaining_int "%.0f" "$remaining"
    if   [ "$remaining_int" -lt "$CTX_CRIT" ]; then ctx_color=$C_ACCENT_CRIT
    elif [ "$remaining_int" -lt "$CTX_WARN" ]; then ctx_color=$C_ACCENT_WARN
    else                                            ctx_color=$C_ACCENT_OK
    fi
    output="${output} ${DIM}|${RESET} ${ctx_color}${remaining_int}%${RESET} ${C_IDENTITY}ctx${RESET}"
fi

if [ -n "$session_cost" ] && [ "$session_cost" != "null" ] && [ "$session_cost" != "0" ]; then
    printf -v cost_fmt '%.2f' "$session_cost"
    output="${output} ${DIM}|${RESET} ${C_IDENTITY}\$${cost_fmt}${RESET}"
fi

printf "%b" "$output"
if [ -n "$five_hr_pct" ] && [ "$five_hr_pct" != "null" ]; then
    printf "\n"
    render_rate_line "5hr" "$five_hr_pct" "$five_hr_reset"
fi
if [ -n "$seven_day_pct" ] && [ "$seven_day_pct" != "null" ]; then
    printf "\n"
    render_rate_line "7day" "$seven_day_pct" "$seven_day_reset"
fi
exit 0
