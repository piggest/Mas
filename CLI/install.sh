#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/usr/local/bin"

# Build first
"$SCRIPT_DIR/build.sh"

# Install
cp "$SCRIPT_DIR/mas-cli" "$INSTALL_DIR/mas-cli"
chmod +x "$INSTALL_DIR/mas-cli"
echo "Installed: $INSTALL_DIR/mas-cli"
