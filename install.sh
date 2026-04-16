#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
SERVICE_LABEL="com.projecthub"
PLIST_NAME="${SERVICE_LABEL}.plist"
SIGN_IDENTITY="ProjectHub Self-Signed"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

cd "$(dirname "$0")"

# --- Stable code signing identity ---
# Swift's default ad-hoc signature changes every rebuild, which makes TCC
# treat the new binary as a stranger and invalidate the Accessibility grant.
# A persistent self-signed cert in the login keychain gives every rebuild
# the same designated requirement, so the grant sticks.
ensure_signing_identity() {
    # Count certificates with our common name. We use find-certificate rather
    # than find-identity because a cert can exist without the codesigning
    # policy predicate matching — if we miss it here, the create branch below
    # silently produces a duplicate, and codesign later bails with
    # "ambiguous (matches ... and ...)".
    local cert_count
    cert_count=$(security find-certificate -a -c "$SIGN_IDENTITY" -Z "$LOGIN_KEYCHAIN" 2>/dev/null \
        | grep -c "^SHA-1 hash:" || true)

    if [ "$cert_count" -gt 1 ]; then
        cat >&2 <<EOF
ERROR: found $cert_count '$SIGN_IDENTITY' certificates in the login keychain.
codesign needs exactly one. Clean them up with either:

  GUI:  Keychain Access → login → search "ProjectHub" → select all → ⌘-Delete
  CLI:  while security find-certificate -c "$SIGN_IDENTITY" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; do
            security delete-certificate -c "$SIGN_IDENTITY" "$LOGIN_KEYCHAIN" || break
        done

Then re-run this installer.
EOF
        exit 1
    fi

    if [ "$cert_count" -eq 1 ]; then
        return 0
    fi

    echo "Creating self-signed code signing certificate '$SIGN_IDENTITY'..."
    local tmpdir
    tmpdir=$(mktemp -d)

    cat > "$tmpdir/ext.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no
[dn]
CN = $SIGN_IDENTITY
[v3_ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

    /usr/bin/openssl genrsa -out "$tmpdir/key.pem" 2048 2>/dev/null
    /usr/bin/openssl req -x509 -new -nodes -key "$tmpdir/key.pem" -sha256 \
        -days 3650 -out "$tmpdir/cert.pem" -config "$tmpdir/ext.conf" 2>/dev/null
    # LibreSSL's empty-password p12 MAC doesn't verify under macOS's
    # `security import` — use a transient password instead. The p12 is
    # deleted seconds after the import, so the value is just a bridge.
    local pw="projecthub-transient-$$"
    /usr/bin/openssl pkcs12 -export \
        -out "$tmpdir/cert.p12" -inkey "$tmpdir/key.pem" -in "$tmpdir/cert.pem" \
        -name "$SIGN_IDENTITY" -passout "pass:$pw" 2>/dev/null

    security import "$tmpdir/cert.p12" \
        -k "$LOGIN_KEYCHAIN" \
        -T /usr/bin/codesign -P "$pw" >/dev/null

    rm -rf "$tmpdir"

    echo "Certificate installed. macOS may prompt once for keychain access"
    echo "the first time codesign uses it — click 'Always Allow'."
}

ensure_signing_identity

echo "Building ProjectHub (release)..."
swift build -c release 2>&1

echo "Signing binary with '$SIGN_IDENTITY'..."
codesign --force --sign "$SIGN_IDENTITY" \
    --preserve-metadata=identifier,entitlements \
    .build/release/ProjectHub

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

launchctl bootout "gui/$(id -u)/$SERVICE_LABEL" 2>/dev/null || true
killall projecthub 2>/dev/null || true
killall ProjectHub 2>/dev/null || true

launchctl bootstrap "gui/$(id -u)" "$PLIST_DIR/$PLIST_NAME"

echo ""
echo "Done! ProjectHub is now running in your menu bar."
echo "It will auto-start on login."
echo ""
echo "First run: you'll be asked to grant Accessibility permission."
echo "The binary is signed with a stable identity, so that grant will"
echo "persist across future reinstalls — no need to re-toggle it in Settings."
echo ""
echo "To uninstall:  bash $(pwd)/uninstall.sh"
