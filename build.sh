#!/bin/bash
# Build ClipHistory.app and install it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/ClipHistory.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClipHistory "$APP/Contents/MacOS/ClipHistory"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipHistory</string>
    <key>CFBundleIdentifier</key><string>net.demul.cliphistory</string>
    <key>CFBundleExecutable</key><string>ClipHistory</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/ClipHistory.app
cp -R "$APP" ~/Applications/
echo "Installed ~/Applications/ClipHistory.app"
