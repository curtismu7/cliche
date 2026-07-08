#!/bin/bash
# Resets Screen Recording permission for Cliché and relaunches a single copy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "── Reset Cliché Screen Recording permission ──"

"$SCRIPT_DIR/install-cleanup.sh" keep

APP="/Applications/Cliche.app"
if [ ! -d "$APP" ]; then
    echo "❌ $APP not found."
    echo "   Install with: brew install --cask cliche"
    echo "   (after: brew tap curtismu7/cliche)"
    exit 1
fi

echo ""
echo "Next steps (manual — macOS requires this):"
echo "  1. System Settings → Privacy & Security → Screen & System Audio Recording"
echo "  2. Confirm NO stale Cliché entries remain (toggle off any you see)"
echo "  3. Press Enter here to launch Cliché…"
read -r _

open "$APP"

"$SCRIPT_DIR/postinstall-hint.sh"

cat <<'EOF'

If you upgrade with Homebrew, run this script again after each release — each build gets a new signature:
  brew update && brew upgrade --cask cliche
  Scripts/fix-screen-recording.sh
EOF
