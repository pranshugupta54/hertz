#!/bin/bash
# Render the app icon and compile it to AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")"

swift makeicon.swift
iconutil -c icns -o AppIcon.icns AppIcon.iconset
rm -rf AppIcon.iconset
echo "Done - scripts/AppIcon.icns"
