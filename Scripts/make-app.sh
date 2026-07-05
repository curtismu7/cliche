#!/bin/bash
# Builds Cliche in release mode and assembles build/Cliche.app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Cliche

APP=build/Cliche.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Cliche "$APP/Contents/MacOS/Cliche"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Cliche</string>
    <key>CFBundleIdentifier</key>
    <string>org.coachcurtis.cliche</string>
    <key>CFBundleName</key>
    <string>Cliché</string>
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
