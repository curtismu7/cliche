#!/bin/bash
# Builds a shareable zip: Cliche.app + double-clickable installer + readme.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/make-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
    build/Cliche.app/Contents/Info.plist 2>/dev/null || echo "0.1.0")
STAGE="build/dist/Cliché"
rm -rf build/dist
mkdir -p "$STAGE"

ditto build/Cliche.app "$STAGE/Cliche.app"
cp Scripts/install.sh "$STAGE/Install Cliché.command"
chmod +x "$STAGE/Install Cliché.command"

cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
Cliché — clipboard history + screen capture for macOS
======================================================

To install:
  1. Double-click "Install Cliché.command".
     If macOS says it "cannot be opened because it is from an
     unidentified developer": right-click (or Control-click) the file
     and choose Open, then Open again. This is normal for apps shared
     outside the App Store.
  2. Follow the prompts. Cliché appears in your menu bar.

Requires macOS 14 (Sonoma) or newer.

Everything stays on your Mac — no accounts, no network. Clipboard
history, screenshots, and settings live in
~/Library/Application Support/Cliche/.

To uninstall: quit Cliché from the panel, delete
/Applications/Cliche.app and the folder above, and remove it from
System Settings → Login Items if you enabled that.
EOF

ZIP="build/Cliche-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$STAGE" "$ZIP"

# DMG: the familiar drag-to-Applications experience. Note for recipients:
# the app is ad-hoc signed, so first launch is right-click → Open (the
# zip's installer clears quarantine automatically; a DMG can't).
DMG="build/Cliche-$VERSION.dmg"
DMG_STAGE="build/dmg"
rm -rf "$DMG_STAGE" "$DMG"
mkdir -p "$DMG_STAGE"
ditto build/Cliche.app "$DMG_STAGE/Cliche.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$STAGE/READ ME FIRST.txt" "$DMG_STAGE/READ ME FIRST.txt"
hdiutil create -volname "Cliché $VERSION" -srcfolder "$DMG_STAGE" \
    -ov -format UDZO -quiet "$DMG"

echo "──────────────────────────────────────────────"
echo "Distributables ready: $ZIP + $DMG"
echo "Zip: double-click 'Install Cliché.command'. DMG: drag to Applications."
