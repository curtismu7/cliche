#!/bin/bash
# Cliché installer — shipped inside the distribution zip as
# "Install Cliché.command" so recipients can just double-click it.
# Recommended install: brew tap curtismu7/cliche && brew install --cask cliche
set -euo pipefail
cd "$(dirname "$0")"

echo "── Installing Cliché ──────────────────────────────"

if [ ! -d "Cliche.app" ]; then
    echo "❌ Cliche.app not found next to this script."
    echo "   Unzip the whole folder first, then run this again."
    exit 1
fi

DEST="/Applications/Cliche.app"
SOURCE="$(pwd)/Cliche.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/install-cleanup.sh"

if ! ditto "Cliche.app" "$DEST" 2>/dev/null; then
    echo "   macOS needs your password to install into Applications…"
    osascript -e "do shell script \"rm -rf '$DEST' && ditto '$SOURCE' '$DEST'\" with administrator privileges"
fi

# The app is signed ad hoc (no Apple Developer certificate), so macOS
# quarantines it after download. Clear that so it can launch.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

read -r -p "Launch Cliché automatically at login? [y/N] " REPLY || REPLY=""
if [[ "$REPLY" =~ ^[Yy] ]]; then
    osascript -e "tell application \"System Events\" to if not (exists login item \"Cliche\") then make login item at end with properties {path:\"$DEST\", hidden:false}" >/dev/null 2>&1 \
        && echo "   Added to Login Items." \
        || echo "   Could not add login item (you can do it in System Settings → Login Items)."
fi

open "$DEST"

"$SCRIPT_DIR/postinstall-hint.sh"

cat <<'EOF'

✅ Cliché is installed (/Applications/Cliche.app) and running —
   look for its icons in the menu bar (or use ⌥1 / ⌥2).

First-run permissions (macOS asks once each):
  • Screen Recording — prompted at your first screenshot
    (System Settings → Privacy & Security → Screen & System Audio Recording,
     then quit and reopen Cliché)
  • Accessibility — only if you use direct paste (⌥-click / ⌥Return)

Getting started:
  ⌥1  clipboard list at cursor   ⌥2  capture panel
  ⌃⌥⌘C  clipboard list (alt)      ⌘⇧6  capture a region
  Gear icon → Panel Appearance (light/dark, header color), hotkeys, limits
  The ? button in the panel lists everything.

Already installed? Upgrade with Homebrew:
  brew update && brew upgrade --cask cliche
Or download the latest release from:
  https://github.com/curtismu7/cliche/releases/latest
EOF
