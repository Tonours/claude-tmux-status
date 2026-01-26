#!/bin/bash
# ============================================================================
# TEST SUITE - Claude tmux status
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { ((PASSED++)); echo -e "${GREEN}✓${NC} $1"; }
fail() { ((FAILED++)); echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${YELLOW}→${NC} $1"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude tmux status - Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# Test: Scripts exist
# ============================================================================
info "Checking scripts exist..."

[[ -f "$SCRIPT_DIR/claude-usage.sh" ]] && pass "claude-usage.sh exists" || fail "claude-usage.sh missing"
[[ -f "$SCRIPT_DIR/tmux-status.sh" ]] && pass "tmux-status.sh exists" || fail "tmux-status.sh missing"
[[ -f "$SCRIPT_DIR/install.sh" ]] && pass "install.sh exists" || fail "install.sh missing"

# ============================================================================
# Test: Scripts are executable
# ============================================================================
info "Checking scripts are executable..."

[[ -x "$SCRIPT_DIR/claude-usage.sh" ]] && pass "claude-usage.sh is executable" || fail "claude-usage.sh not executable"
[[ -x "$SCRIPT_DIR/tmux-status.sh" ]] && pass "tmux-status.sh is executable" || fail "tmux-status.sh not executable"
[[ -x "$SCRIPT_DIR/install.sh" ]] && pass "install.sh is executable" || fail "install.sh not executable"

# ============================================================================
# Test: Python 3 available
# ============================================================================
info "Checking Python 3..."

if command -v python3 &>/dev/null; then
    pass "Python 3 is available ($(python3 --version 2>&1 | cut -d' ' -f2))"
else
    fail "Python 3 not found"
fi

# ============================================================================
# Test: Bash syntax
# ============================================================================
info "Checking bash syntax..."

if bash -n "$SCRIPT_DIR/claude-usage.sh" 2>/dev/null; then
    pass "claude-usage.sh syntax OK"
else
    fail "claude-usage.sh syntax error"
fi

if bash -n "$SCRIPT_DIR/tmux-status.sh" 2>/dev/null; then
    pass "tmux-status.sh syntax OK"
else
    fail "tmux-status.sh syntax error"
fi

# ============================================================================
# Test: Help command
# ============================================================================
info "Checking help command..."

if "$SCRIPT_DIR/claude-usage.sh" help 2>/dev/null | grep -q "Usage:"; then
    pass "claude-usage.sh help works"
else
    fail "claude-usage.sh help broken"
fi

# ============================================================================
# Test: No config error
# ============================================================================
info "Checking error handling..."

export CLAUDE_USAGE_CONFIG="/tmp/nonexistent-config-$$"
result=$("$SCRIPT_DIR/claude-usage.sh" 2>/dev/null || true)
if [[ "$result" == "ERROR:NO_CONFIG" ]]; then
    pass "Missing config returns ERROR:NO_CONFIG"
else
    fail "Missing config should return ERROR:NO_CONFIG, got: $result"
fi
unset CLAUDE_USAGE_CONFIG

# ============================================================================
# Test: Cache functionality
# ============================================================================
info "Checking cache..."

CACHE_DIR=$(mktemp -d)
export CLAUDE_USAGE_CACHE="$CACHE_DIR/cache"
export CLAUDE_USAGE_CONFIG="$CACHE_DIR/config"

# Create fake config with valid format
cat > "$CLAUDE_USAGE_CONFIG" << 'EOF'
CLAUDE_SESSION_KEY="sk-ant-sid01-fake-key"
CLAUDE_ORG_ID="12345678-1234-1234-1234-123456789abc"
EOF

# Create fake cache with current timestamp (will be valid for 30s)
echo "42|2026-01-01T00:00:00+00:00" > "$CLAUDE_USAGE_CACHE"
# Touch with current time to ensure cache is fresh
touch "$CLAUDE_USAGE_CACHE"

result=$("$SCRIPT_DIR/claude-usage.sh" 2>/dev/null || true)
if [[ "$result" == "42|2026-01-01T00:00:00+00:00" ]]; then
    pass "Cache is used when valid"
else
    fail "Cache should be used, got: $result"
fi

rm -rf "$CACHE_DIR"
unset CLAUDE_USAGE_CACHE CLAUDE_USAGE_CONFIG

# ============================================================================
# Test: tmux-status output format
# ============================================================================
info "Checking tmux-status output format..."

# Create mock claude-usage.sh that returns test data
MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/claude-usage.sh" << 'EOF'
#!/bin/bash
echo "50|2026-01-26T15:00:00+00:00"
EOF
chmod +x "$MOCK_DIR/claude-usage.sh"

# Use CLAUDE_USAGE_SCRIPT env var to override
export CLAUDE_USAGE_SCRIPT="$MOCK_DIR/claude-usage.sh"
result=$("$SCRIPT_DIR/tmux-status.sh" 2>/dev/null || true)
unset CLAUDE_USAGE_SCRIPT

if [[ "$result" == *"#[fg="* ]] && [[ "$result" == *"%"* ]] && [[ "$result" == *"50%"* ]]; then
    pass "tmux-status output has correct format"
else
    fail "tmux-status output format incorrect: $result"
fi

rm -rf "$MOCK_DIR"

# ============================================================================
# Test: Utilization boundary colors
# ============================================================================
info "Checking utilization boundary colors..."

test_color() {
    local util="$1" expected_color="$2"
    local mock_dir=$(mktemp -d)
    cat > "$mock_dir/claude-usage.sh" << EOF
#!/bin/bash
echo "${util}|2026-01-26T15:00:00+00:00"
EOF
    chmod +x "$mock_dir/claude-usage.sh"

    export CLAUDE_USAGE_SCRIPT="$mock_dir/claude-usage.sh"
    local result=$("$SCRIPT_DIR/tmux-status.sh" 2>/dev/null || true)
    unset CLAUDE_USAGE_SCRIPT
    rm -rf "$mock_dir"

    if [[ "$result" == *"$expected_color"* ]]; then
        pass "Utilization ${util}% uses $expected_color"
    else
        fail "Utilization ${util}% should use $expected_color, got: $result"
    fi
}

test_color "0" "colour114"    # Green (0-30%)
test_color "30" "colour114"   # Green boundary
test_color "31" "colour223"   # Yellow (31-50%)
test_color "50" "colour223"   # Yellow boundary
test_color "51" "colour216"   # Peach (51-70%)
test_color "100" "colour211"  # Red (91-100%)

# ============================================================================
# Test: Decimal utilization handling
# ============================================================================
info "Checking decimal utilization handling..."

MOCK_DIR=$(mktemp -d)
cat > "$MOCK_DIR/claude-usage.sh" << 'EOF'
#!/bin/bash
echo "45.7|2026-01-26T15:00:00+00:00"
EOF
chmod +x "$MOCK_DIR/claude-usage.sh"

export CLAUDE_USAGE_SCRIPT="$MOCK_DIR/claude-usage.sh"
result=$("$SCRIPT_DIR/tmux-status.sh" 2>/dev/null || true)
unset CLAUDE_USAGE_SCRIPT
rm -rf "$MOCK_DIR"

if [[ "$result" == *"45%"* ]]; then
    pass "Decimal utilization truncated correctly"
else
    fail "Decimal utilization should show 45%, got: $result"
fi

# ============================================================================
# Test: Config validation
# ============================================================================
info "Checking config validation..."

CACHE_DIR=$(mktemp -d)
export CLAUDE_USAGE_CONFIG="$CACHE_DIR/config"

# Create config with invalid content (potential injection)
cat > "$CLAUDE_USAGE_CONFIG" << 'EOF'
CLAUDE_SESSION_KEY="valid"
echo "INJECTED"
CLAUDE_ORG_ID="valid"
EOF

result=$("$SCRIPT_DIR/claude-usage.sh" 2>/dev/null || true)
if [[ "$result" == "ERROR:INVALID_CONFIG" ]]; then
    pass "Invalid config detected"
else
    fail "Invalid config should be rejected, got: $result"
fi

rm -rf "$CACHE_DIR"
unset CLAUDE_USAGE_CONFIG

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

[[ $FAILED -eq 0 ]] && exit 0 || exit 1
