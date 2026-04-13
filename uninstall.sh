#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
SERVICE_LABEL="com.projecthub"
PLIST_NAME="${SERVICE_LABEL}.plist"

launchctl bootout "gui/$(id -u)/$SERVICE_LABEL" 2>/dev/null || true
killall projecthub 2>/dev/null || true
killall ProjectHub 2>/dev/null || true

rm -f "$PLIST_DIR/$PLIST_NAME"
rm -f "$INSTALL_DIR/projecthub"

echo "ProjectHub uninstalled."
echo "(Your projects.json at ~/Library/Application Support/ProjectHub/ was left in place.)"
