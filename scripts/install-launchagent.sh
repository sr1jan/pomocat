#!/usr/bin/env bash
# install-launchagent.sh — Install fatcat as a per-user LaunchAgent.
# fatcat starts at every login and restarts automatically on crash.
#
# Idempotent: re-run after `git pull` or rebuild and it'll reload cleanly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$REPO_ROOT/.build/release/fatcat"
TEMPLATE="$REPO_ROOT/scripts/launchagent.plist.template"
PLIST_DEST="$HOME/Library/LaunchAgents/com.fatcat.plist"

# Always rebuild — swift build is incremental and nearly free when nothing
# changed, but skipping this on reinstall would silently ship a stale binary
# (e.g. one built with debug-only durations from an earlier session).
echo "==> building release binary"
(cd "$REPO_ROOT" && swift build -c release)

# Substitute absolute paths into the template.
mkdir -p "$(dirname "$PLIST_DEST")"
sed -e "s|__BINARY__|$BINARY|g" \
    -e "s|__REPO__|$REPO_ROOT|g" \
    "$TEMPLATE" > "$PLIST_DEST"

# Reload (unload + load = the idempotent way to apply changes).
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

echo "Installed."
echo "  Plist:   $PLIST_DEST"
echo "  Logs:    $REPO_ROOT/.fatcat.log"
echo "  Binary:  $BINARY"
echo
echo "fatcat is now running and will restart at every login."
echo "To stop: scripts/uninstall-launchagent.sh"
