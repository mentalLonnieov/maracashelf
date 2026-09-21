#!/bin/bash
# Builds MaracaShelf and packages it as a real .app bundle so macOS treats it as a proper
# background application (no Dock icon, stable identity for Accessibility permission, etc).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MaracaShelf"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
CONFIG="${1:-release}"

echo "==> Building ($CONFIG)..."
cd "$ROOT_DIR"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Packaging $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/"*.png "$APP_BUNDLE/Contents/Resources/"
cp -R "$ROOT_DIR/Resources/"*.lproj "$APP_BUNDLE/Contents/Resources/"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.maracashelf</string>
    <key>CFBundleVersion</key>
    <string>0.1.2</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.2</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ru</string>
        <string>uk</string>
        <string>pl</string>
        <string>cs</string>
        <string>de</string>
    </array>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
</dict>
</plist>
PLIST

echo "==> Codesigning (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
echo "    Run:  open \"$APP_BUNDLE\""
