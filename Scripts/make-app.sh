#!/bin/bash
# Builds Cliche in release mode and assembles build/Cliche.app.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"

swift build -c release --product Cliche

APP=build/Cliche.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cliche "$APP/Contents/MacOS/Cliche"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Cliche</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>org.coachcurtis.cliche</string>
    <key>CFBundleName</key>
    <string>Cliché</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>org.coachcurtis.cliche.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>cliche</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS treats the bundle as a stable identity for the
# Screen Recording permission.
codesign --force --sign - "$APP"

echo "Built $APP"
