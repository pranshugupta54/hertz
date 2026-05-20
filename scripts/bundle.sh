#!/bin/bash
# Build Hertz as a release .app bundle.
# Version comes from $HERTZ_VERSION, else the latest git tag, else 0.0.0-dev.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Hertz.app"
CONTENTS="$APP/Contents"
VERSION="${HERTZ_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
VERSION="${VERSION#v}"            # strip leading v from a tag like v0.1.0
VERSION="${VERSION:-0.0.0-dev}"

echo "Building Hertz $VERSION ..."
swift build -c release --product Hertz

echo "Assembling $APP ..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp .build/release/Hertz "$CONTENTS/MacOS/Hertz"
cp scripts/Info.plist "$CONTENTS/Info.plist"
cp scripts/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Stamp the real version so the in-app updater compares correctly.
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"

# Ad-hoc signature so macOS runs it locally without Gatekeeper friction.
codesign --force --sign - "$APP"

echo "Done - $APP ($VERSION)"
