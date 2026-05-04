#!/usr/bin/env bash
set -euo pipefail

APP="BlindSpot-Dev.app"
BINARY=".build/debug/BlindSpot"

echo "Building..."
swift build 2>&1 | grep -E "error:|Build complete"

echo "Packaging ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"

ln -s "$(pwd)/${BINARY}" "${APP}/Contents/MacOS/BlindSpot"

cat > "${APP}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.blindspot.app.dev</string>
    <key>CFBundleName</key>
    <string>BlindSpot-Dev</string>
    <key>CFBundleExecutable</key>
    <string>BlindSpot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>dev</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>BlindSpot reads your selected text to answer questions about it.</string>
</dict>
</plist>
PLIST

echo "Done -> ${APP}"
echo ""
echo "First time? Add to System Settings -> Privacy & Security -> Accessibility"
echo ""

if [[ "${1:-}" == "--run" ]]; then
    pkill BlindSpot 2>/dev/null || true
    sleep 0.3
    open "${APP}"
    echo "Launched."
fi
