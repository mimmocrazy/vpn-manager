#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.local/bin"
TARGET_BIN="$TARGET_DIR/vpn"

mkdir -p "$TARGET_DIR"
chmod +x "$SCRIPT_DIR/vpn.sh"
ln -sf "$SCRIPT_DIR/vpn.sh" "$TARGET_BIN"

echo "✔ Linked $SCRIPT_DIR/vpn.sh -> $TARGET_BIN"
echo "✔ Run 'vpn --help' to get started."
