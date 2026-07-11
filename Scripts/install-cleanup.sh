#!/bin/bash
# Removes duplicate Cliché installs and resets Screen Recording TCC.
# Pass "keep" as the first argument to reset permission without removing
# /Applications/Cliche.app (for fix-screen-recording.sh).
set -euo pipefail

BUNDLE_ID="org.coachcurtis.cliche"
INSTALL_PATH="/Applications/Cliche.app"
HOME_COPY="${HOME}/Applications/Cliche.app"
KEEP_INSTALL="${1:-}"

echo "── Cleaning up Cliché installs ──"

pkill -f 'Cliche.app/Contents/MacOS/Cliche' 2>/dev/null || true
sleep 1

if [ -d "$HOME_COPY" ]; then
    echo "Removing duplicate: $HOME_COPY"
    rm -rf "$HOME_COPY"
    echo "Resetting Screen Recording permission for ${BUNDLE_ID} (duplicate removed)..."
    tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
fi

if [ -z "$KEEP_INSTALL" ] && [ -d "$INSTALL_PATH" ]; then
    echo "Updating in place: $INSTALL_PATH (permissions preserved — toggle OFF/ON if capture breaks after update)"
fi
