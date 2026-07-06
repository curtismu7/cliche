#!/bin/bash
# Resets Screen Recording permission for Cliché and relaunches a single copy.
set -euo pipefail

echo "── Reset Cliché Screen Recording permission ──"

pkill -f 'Cliche.app/Contents/MacOS/Cliche' 2>/dev/null || true
sleep 1

if [ -d "$HOME/Applications/Cliche.app" ]; then
    echo "Removing duplicate: ~/Applications/Cliche.app (old install location)"
    rm -rf "$HOME/Applications/Cliche.app"
fi

echo "Resetting TCC entry for org.coachcurtis.cliche…"
tccutil reset ScreenCapture org.coachcurtis.cliche 2>/dev/null || true

APP="/Applications/Cliche.app"
if [ ! -d "$APP" ]; then
    echo "❌ $APP not found."
    echo "   Install with: make install   (from source)"
    echo "   Or unzip the release and run Install Cliché.command"
    exit 1
fi

echo ""
echo "Next steps (manual — macOS requires this):"
echo "  1. System Settings → Privacy & Security → Screen & System Audio Recording"
echo "  2. Confirm NO stale Cliché entries remain (toggle off any you see)"
echo "  3. Press Enter here to launch Cliché…"
read -r _

open "$APP"

cat <<'EOF'

When Cliché opens:
  • Turn Cliché ON in Screen & System Audio Recording.
  • Quit Cliché completely, then open it again once (required after toggling).
  • Try ⌃⌥⌘4 to capture.

If you rebuild from source, run this script again — each build gets a new signature.
EOF
