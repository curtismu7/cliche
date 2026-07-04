#!/bin/bash
# Builds ClipShot in release mode and assembles build/ClipShot.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ClipShot

APP=build/ClipShot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClipShot "$APP/Contents/MacOS/ClipShot"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClipShot</string>
    <key>CFBundleIdentifier</key>
    <string>org.coachcurtis.clipshot</string>
    <key>CFBundleName</key>
    <string>ClipShot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as a stable identity for the
# Screen Recording permission.
codesign --force --sign - "$APP"

echo "Built $APP"
