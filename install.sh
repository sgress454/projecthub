#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="com.projecthub.plist"

cd "$(dirname "$0")"

echo "Building ProjectHub (release)..."
swift build -c release 2>&1

echo "Installing binary to $INSTALL_DIR/projecthub..."
mkdir -p "$INSTALL_DIR"
cp -f .build/release/ProjectHub "$INSTALL_DIR/projecthub"

echo "Installing launch agent..."
mkdir -p "$PLIST_DIR"
cat > "$PLIST_DIR/$PLIST_NAME" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.projecthub</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/projecthub</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$PLIST_NAME" 2>/dev/null || true
killall projecthub 2>/dev/null || true
killall ProjectHub 2>/dev/null || true

launchctl bootstrap "gui/$(id -u)" "$PLIST_DIR/$PLIST_NAME"

echo ""
echo "Done! ProjectHub is now running in your menu bar."
echo "It will auto-start on login."
echo ""
echo "First run: you'll be asked to grant Accessibility permission."
echo "To uninstall:  bash $(pwd)/uninstall.sh"
