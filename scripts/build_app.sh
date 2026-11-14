#!/usr/bin/env bash
# Builds build/MacProject.app (and MacProject.zip) from the Swift package. Run on a Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MacProject
BIN="$(swift build -c release --show-bin-path)/MacProject"

APP="build/MacProject.app"
rm -rf "$APP" build/MacProject.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacProject"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"        # ad-hoc signature so it launches locally
(cd build && ditto -c -k --keepParent MacProject.app MacProject.zip)
echo "Built $APP"
