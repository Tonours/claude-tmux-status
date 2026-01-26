#!/bin/bash
# ============================================================================
# TMUX-STATUS - Display Claude.ai usage in tmux status bar
# https://github.com/Tonours/claude-tmux-status
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow override via environment variable
if [[ -n "${CLAUDE_USAGE_SCRIPT:-}" ]] && [[ -f "$CLAUDE_USAGE_SCRIPT" ]]; then
    CLAUDE_USAGE="$CLAUDE_USAGE_SCRIPT"
else
    CLAUDE_USAGE="${SCRIPT_DIR}/claude-usage.sh"

    # Fallback paths
    [[ ! -f "$CLAUDE_USAGE" ]] && CLAUDE_USAGE="$HOME/.local/bin/claude-usage.sh"
    [[ ! -f "$CLAUDE_USAGE" ]] && CLAUDE_USAGE="/usr/local/bin/claude-usage.sh"
fi

if [[ ! -f "$CLAUDE_USAGE" ]]; then
    echo "#[fg=colour240]claude: ?#[default]"
    exit 0
fi

# Fetch usage
result=$("$CLAUDE_USAGE" 2>/dev/null)

if [[ $? -ne 0 ]] || [[ "$result" == ERROR:* ]]; then
    echo "#[fg=colour240]claude: -#[default]"
    exit 0
fi

# Parse result (format: utilization|resets_at)
utilization=$(echo "$result" | cut -d'|' -f1)
resets_at=$(echo "$result" | cut -d'|' -f2)

# Support both integer and decimal utilization values
if [[ -z "$utilization" ]] || ! [[ "$utilization" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    echo "#[fg=colour240]claude: ?#[default]"
    exit 0
fi

# Truncate decimal to integer for display
utilization=${utilization%%.*}

# Catppuccin Mocha colors
# Green: colour114, Yellow: colour223, Peach: colour216, Orange: colour209, Red: colour211
# Mauve: colour183, Surface0: colour237, Overlay0: colour245

if [[ $utilization -le 30 ]]; then
    color="colour114"  # Green
elif [[ $utilization -le 50 ]]; then
    color="colour223"  # Yellow
elif [[ $utilization -le 70 ]]; then
    color="colour216"  # Peach
elif [[ $utilization -le 90 ]]; then
    color="colour209"  # Orange
else
    color="colour211"  # Red
fi

# Progress bar (10 chars)
total=10
filled=$(( (utilization * total + 50) / 100 ))
[[ $filled -gt $total ]] && filled=$total
[[ $filled -lt 0 ]] && filled=0
empty=$((total - filled))

bar=""
for ((i=0; i<filled; i++)); do bar+="━"; done
for ((i=0; i<empty; i++)); do bar+="─"; done

# Time remaining
reset_info=""
if [[ -n "$resets_at" ]] && [[ "$resets_at" != "null" ]]; then
    # Parse ISO 8601 timestamp
    # Remove microseconds and timezone for consistent parsing
    iso_time=$(echo "$resets_at" | sed 's/\.[0-9]*//;s/[+-][0-9:]*$//')

    reset_epoch=""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date command
        reset_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$iso_time" "+%s" 2>/dev/null) || true
    else
        # Linux date command - try multiple formats
        reset_epoch=$(date -d "$resets_at" "+%s" 2>/dev/null) || \
        reset_epoch=$(date -d "$iso_time" "+%s" 2>/dev/null) || true
    fi

    # Validate reset_epoch is a number
    if [[ -n "$reset_epoch" ]] && [[ "$reset_epoch" =~ ^[0-9]+$ ]]; then
        now_epoch=$(date +%s)
        diff=$((reset_epoch - now_epoch))

        if [[ $diff -gt 0 ]]; then
            hours=$((diff / 3600))
            mins=$(((diff % 3600) / 60))

            if [[ $hours -gt 0 ]]; then
                reset_info="#[fg=colour245] ⟳${hours}h${mins}m"
            else
                reset_info="#[fg=colour245] ⟳${mins}m"
            fi
        fi
    fi
fi

# Output with Catppuccin styling
echo "#[fg=colour183]✦#[fg=$color] ${utilization}%#[fg=colour237] [#[fg=$color]${bar}#[fg=colour237]]${reset_info}#[default]"
