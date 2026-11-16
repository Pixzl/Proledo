#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Proledo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Proledo "$APP/Contents/MacOS/Proledo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Proledo.icns "$APP/Contents/Resources/Proledo.icns"
codesign --force --sign - "$APP" >/dev/null

echo "Fertig: $(pwd)/$APP"
