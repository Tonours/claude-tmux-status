#!/bin/bash
# ============================================================================
# CLAUDE-USAGE - Fetch Claude.ai usage via API
# https://github.com/Tonours/claude-tmux-status
# ============================================================================

set -euo pipefail

CONFIG_FILE="${CLAUDE_USAGE_CONFIG:-$HOME/.config/claude-usage/config}"
CACHE_FILE="${CLAUDE_USAGE_CACHE:-$HOME/.config/claude-usage/cache}"
CACHE_TTL="${CLAUDE_USAGE_CACHE_TTL:-30}"
DEBUG="${DEBUG:-0}"

# Debug logging
debug() {
    [[ "$DEBUG" == "1" ]] && echo "DEBUG: $*" >&2 || true
}

# Save cache with proper permissions
save_cache() {
    local content="$1"
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$content" > "$CACHE_FILE"
    chmod 600 "$CACHE_FILE"
}

# Validate config file before sourcing (prevent code injection)
validate_config() {
    local file="$1"
    # Only allow variable assignments with expected format
    if grep -qvE '^(#.*|CLAUDE_SESSION_KEY="[^"]*"|CLAUDE_ORG_ID="[^"]*"|[[:space:]]*)$' "$file" 2>/dev/null; then
        echo "ERROR:INVALID_CONFIG"
        exit 1
    fi
}

# Load config
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR:NO_CONFIG"
        exit 1
    fi

    validate_config "$CONFIG_FILE"
    source "$CONFIG_FILE"

    if [[ -z "${CLAUDE_SESSION_KEY:-}" ]] || [[ -z "${CLAUDE_ORG_ID:-}" ]]; then
        echo "ERROR:MISSING_CREDS"
        exit 1
    fi
}

# Check cache validity
cache_valid() {
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_time now age
        if [[ "$OSTYPE" == "darwin"* ]]; then
            cache_time=$(stat -f %m "$CACHE_FILE" 2>/dev/null)
        else
            cache_time=$(stat -c %Y "$CACHE_FILE" 2>/dev/null)
        fi
        now=$(date +%s)
        age=$((now - cache_time))
        [[ $age -lt $CACHE_TTL ]] && return 0
    fi
    return 1
}

# Fetch usage from API
fetch_usage() {
    load_config

    # Use cache if valid
    if cache_valid; then
        debug "Using cached data"
        cat "$CACHE_FILE"
        return 0
    fi

    local result

    # Try Python (available on macOS/Linux)
    # Pass credentials via environment variables to avoid exposure in ps
    if command -v python3 &>/dev/null; then
        debug "Fetching via Python"
        result=$(CLAUDE_SK="$CLAUDE_SESSION_KEY" CLAUDE_ORG="$CLAUDE_ORG_ID" python3 << 'PYTHON'
import os, json, urllib.request
session_key = os.environ.get("CLAUDE_SK", "")
org_id = os.environ.get("CLAUDE_ORG", "")
url = f"https://claude.ai/api/organizations/{org_id}/usage"
req = urllib.request.Request(url, headers={
    "Cookie": f"sessionKey={session_key}",
    "Accept": "application/json",
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
})
try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.load(resp)
        util = data.get("five_hour", {}).get("utilization", 0)
        # Handle both int and float utilization values
        util = int(float(util)) if util else 0
        resets = data.get("five_hour", {}).get("resets_at", "")
        print(f"{util}|{resets}")
except Exception as e:
    print(f"ERROR:{e}")
    exit(1)
PYTHON
        )

        if [[ ! "$result" =~ ^ERROR: ]] && [[ -n "$result" ]]; then
            save_cache "$result"
            echo "$result"
            return 0
        fi
    fi

    # Curl fallback - use env var in subshell to avoid ps exposure
    debug "Fetching via curl"
    local response http_code body
    response=$(curl -s -w "\n%{http_code}" \
        --connect-timeout 5 \
        --max-time 10 \
        -H "Cookie: sessionKey=${CLAUDE_SESSION_KEY}" \
        -H "Accept: application/json" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
        "https://claude.ai/api/organizations/${CLAUDE_ORG_ID}/usage" 2>/dev/null) || {
        echo "ERROR:NETWORK"
        return 1
    }

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        debug "HTTP error: $http_code"
        [[ -f "$CACHE_FILE" ]] && { cat "$CACHE_FILE"; return 0; }
        echo "ERROR:HTTP_$http_code"
        return 1
    fi

    local utilization resets_at
    if command -v jq &>/dev/null; then
        utilization=$(echo "$body" | jq -r '.five_hour.utilization // empty')
        resets_at=$(echo "$body" | jq -r '.five_hour.resets_at // empty')
    else
        # Support both integer and decimal values
        utilization=$(echo "$body" | grep -oE '"utilization":[0-9.]+' | head -1 | cut -d: -f2)
        resets_at=$(echo "$body" | grep -o '"resets_at":"[^"]*"' | head -1 | sed 's/"resets_at":"//;s/"$//')
    fi

    # Handle decimal utilization (truncate to int)
    if [[ -n "$utilization" ]]; then
        utilization=${utilization%%.*}
    fi

    [[ -z "$utilization" ]] && { echo "ERROR:PARSE"; return 1; }

    result="${utilization}|${resets_at:-}"
    save_cache "$result"
    echo "$result"
}

# Setup wizard
setup() {
    echo "Claude Usage - Setup"
    echo "===================="
    echo ""
    echo "To get your credentials:"
    echo ""
    echo "1. Open https://claude.ai in your browser"
    echo "2. Open DevTools (F12) > Application > Cookies > claude.ai"
    echo "3. Copy 'sessionKey' value (starts with sk-ant-sid01-...)"
    echo ""
    echo "4. Go to https://claude.ai/settings"
    echo "5. Click on any organization setting"
    echo "6. Copy the UUID from the URL (format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
    echo ""

    read -rp "Session Key: " session_key

    # Validate session key format
    if [[ -z "$session_key" ]]; then
        echo "ERROR: Session key cannot be empty"
        exit 1
    fi
    if [[ ! "$session_key" =~ ^sk-ant-sid ]]; then
        echo "WARNING: Session key doesn't match expected format (sk-ant-sid...)"
        read -rp "Continue anyway? [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
    fi

    read -rp "Organization ID: " org_id

    # Validate UUID format
    if [[ -z "$org_id" ]]; then
        echo "ERROR: Organization ID cannot be empty"
        exit 1
    fi
    if [[ ! "$org_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        echo "WARNING: Organization ID doesn't match UUID format"
        read -rp "Continue anyway? [y/N]: " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
    fi

    # Escape special characters in credentials
    session_key_escaped="${session_key//\"/\\\"}"
    org_id_escaped="${org_id//\"/\\\"}"

    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
# Claude.ai credentials
CLAUDE_SESSION_KEY="$session_key_escaped"
CLAUDE_ORG_ID="$org_id_escaped"
EOF
    chmod 600 "$CONFIG_FILE"

    echo ""
    echo "Config saved to $CONFIG_FILE"
    echo "Test with: claude-usage.sh"
}

# Show help
usage() {
    cat << EOF
Claude Usage - Fetch Claude.ai API usage

Usage: claude-usage.sh [command]

Commands:
    (none)    Fetch current usage (output: utilization|resets_at)
    setup     Interactive setup wizard
    help      Show this help

Environment variables:
    CLAUDE_USAGE_CONFIG      Config file path (default: ~/.config/claude-usage/config)
    CLAUDE_USAGE_CACHE       Cache file path (default: ~/.config/claude-usage/cache)
    CLAUDE_USAGE_CACHE_TTL   Cache TTL in seconds (default: 30)

Output format:
    Success: <utilization>|<resets_at>
    Error:   ERROR:<code>

Example:
    $ claude-usage.sh
    28|2024-01-26T15:00:00.000000+00:00
EOF
}

# Main
case "${1:-}" in
    setup)  setup ;;
    help|-h|--help) usage ;;
    *)      fetch_usage ;;
esac
