#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.projecthub.plist"

launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
killall projecthub 2>/dev/null || true
killall ProjectHub 2>/dev/null || true

rm -f "$PLIST_DIR/$PLIST_NAME"
rm -f "$INSTALL_DIR/projecthub"

echo "ProjectHub uninstalled."
echo "(Your projects.json at ~/Library/Application Support/ProjectHub/ was left in place.)"
