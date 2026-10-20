#!/bin/zsh
# Builds a universal (arm64 + x86_64), ad-hoc signed GreeBar.app into ./build
# Usage: ./build-app.sh [version]
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:-$(cat VERSION)}

# SwiftUI macros (@State) ship with Xcode, not the Command Line Tools.
if [[ -d /Applications/Xcode.app ]]; then export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
APP=build/GreeBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release $ARCHS --show-bin-path)/GreeBar" "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>GreeBar</string>
    <key>CFBundleIdentifier</key><string>local.greebar.GreeBar</string>
    <key>CFBundleExecutable</key><string>GreeBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>GreeBar talks to your Gree air conditioner on the local network.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
