#!/bin/bash
# Builds Explorer.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Explorer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Explorer "$APP/Contents/MacOS/Explorer"
cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
    swift scripts/make_icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"
