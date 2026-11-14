#!/usr/bin/env bash
# Builds build/Gantt.app (and Gantt.zip) from the Swift package. Run on a Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Gantt
BIN="$(swift build -c release --show-bin-path)/Gantt"

APP="build/Gantt.app"
rm -rf "$APP" build/Gantt.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Gantt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"        # ad-hoc signature so it launches locally
(cd build && ditto -c -k --keepParent Gantt.app Gantt.zip)
echo "Built $APP"
