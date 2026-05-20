#!/bin/bash
# Remove Hertz from the system.
#
#   curl -fsSL https://raw.githubusercontent.com/pranshugupta54/hertz/main/uninstall.sh | bash
set -euo pipefail

osascript -e 'quit app "Hertz"' 2>/dev/null || true
pkill -x Hertz 2>/dev/null || true
rm -rf "$HOME/Applications/Hertz.app" /Applications/Hertz.app

echo "Hertz uninstalled."
echo "If you enabled 'Launch at login', remove the leftover entry in"
echo "System Settings > General > Login Items."
