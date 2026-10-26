#!/bin/bash
# Build ClipWise.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/ClipWise.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClipWise "$APP/Contents/MacOS/ClipWise"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipWise</string>
    <key>CFBundleIdentifier</key><string>net.demul.clipwise</string>
    <key>CFBundleExecutable</key><string>ClipWise</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/ClipWise.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/ClipWise.app"
