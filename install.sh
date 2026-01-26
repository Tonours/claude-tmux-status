#!/bin/bash
# ============================================================================
# INSTALL - Claude tmux status
# https://github.com/Tonours/claude-tmux-status
# ============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${BLUE}Claude tmux status${NC}"
echo "=================="
echo ""

# Validate source files exist
for file in claude-usage.sh tmux-status.sh; do
    if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
        echo -e "${RED}ERROR: $file not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
done

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy scripts with validation
install_script() {
    local src="$1" dst="$2"
    cp "$src" "$dst" && chmod +x "$dst"
}

echo -e "${GREEN}Installing scripts to $INSTALL_DIR${NC}"
install_script "$SCRIPT_DIR/claude-usage.sh" "$INSTALL_DIR/claude-usage.sh"
install_script "$SCRIPT_DIR/tmux-status.sh" "$INSTALL_DIR/tmux-claude-status.sh"

# Add to PATH if needed
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}Add to your shell config (~/.bashrc or ~/.zshrc):${NC}"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Setup credentials:"
echo -e "     ${YELLOW}claude-usage.sh setup${NC}"
echo ""
echo "  2. Add to your tmux.conf:"
echo -e "     ${YELLOW}set -g status-right \"#($INSTALL_DIR/tmux-claude-status.sh)\"${NC}"
echo ""
echo "  3. Reload tmux:"
echo -e "     ${YELLOW}tmux source-file ~/.tmux.conf${NC}"
echo ""
