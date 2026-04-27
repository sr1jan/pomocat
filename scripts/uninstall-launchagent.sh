#!/usr/bin/env bash
# uninstall-launchagent.sh — Remove the pomocat LaunchAgent.
# Stops the running process and prevents future auto-start.

set -euo pipefail

PLIST_DEST="$HOME/Library/LaunchAgents/com.pomocat.plist"

if [[ ! -f "$PLIST_DEST" ]]; then
    echo "Not installed (no plist at $PLIST_DEST)."
    exit 0
fi

launchctl unload "$PLIST_DEST" 2>/dev/null || true
rm -f "$PLIST_DEST"

echo "Uninstalled. Plist removed."
echo "Any running pomocat process has been stopped (launchctl unload sent SIGTERM)."
