#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.local/bin"
TARGET_BIN="$TARGET_DIR/vpn"

echo -e "\n \033[1;38;5;111m::\033[0m \033[1mInstalling OpenVPN Manager...\033[0m"

mkdir -p "$TARGET_DIR"
chmod +x "$SCRIPT_DIR/vpn.sh"
ln -sf "$SCRIPT_DIR/vpn.sh" "$TARGET_BIN"

echo -e "  \033[38;5;150m✔\033[0m Linked script to \033[1m$TARGET_BIN\033[0m"
echo -e "  \033[38;5;150m✔\033[0m Run \033[1;38;5;141mvpn --help\033[0m to get started.\n"
