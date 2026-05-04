#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$SCRIPT_DIR/mas-cli"

echo "Building mas-cli..."
swiftc \
  -O \
  -framework Foundation \
  -framework AppKit \
  -framework Vision \
  -framework VisionKit \
  -framework ImageIO \
  -framework CoreImage \
  "$SCRIPT_DIR/mas_cli.swift" \
  -o "$OUTPUT"

echo "Built: $OUTPUT"
