#!/bin/bash
# Build ClipWise.app.
#   ./build.sh            build for this Mac and install into ~/Applications
#   ./build.sh --release  universal (Apple Silicon + Intel) build, zipped as build/ClipWise-<version>.zip
set -euo pipefail
cd "$(dirname "$0")"

VERSION=0.1.0
RELEASE=false
[[ "${1:-}" == "--release" ]] && RELEASE=true

ARGS=(-c release)
$RELEASE && ARGS+=(--arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/ClipWise"

APP=build/ClipWise.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClipWise"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipWise</string>
    <key>CFBundleIdentifier</key><string>net.demul.clipwise</string>
    <key>CFBundleExecutable</key><string>ClipWise</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally. Not notarised, so a downloaded copy
# needs "Open Anyway" in System Settings → Privacy & Security the first time.
codesign --force -s - "$APP"

if $RELEASE; then
    ZIP=build/ClipWise-$VERSION.zip
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Release: $ZIP ($(lipo -archs "$APP/Contents/MacOS/ClipWise"))"
else
    mkdir -p ~/Applications
    rm -rf ~/Applications/ClipWise.app
    cp -R "$APP" ~/Applications/
    echo "Installed ~/Applications/ClipWise.app"
fi
