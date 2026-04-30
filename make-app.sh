#!/bin/zsh
# Creates BlindSpot.app in the current directory.
# Usage: ./make-app.sh [version]

set -e
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP="BlindSpot.app"

echo "Building BlindSpot $VERSION…"
swift build -c release 2>&1

# Generate icon if ICNS doesn't exist yet
if [[ ! -f "BlindSpot.icns" ]]; then
    echo "Generating app icon…"
    swift make-icon.swift
fi

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/BlindSpot "$APP/Contents/MacOS/BlindSpot"
cp BlindSpot.icns "$APP/Contents/Resources/BlindSpot.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>      <string>BlindSpot</string>
  <key>CFBundleIdentifier</key>      <string>com.blindspot.app</string>
  <key>CFBundleName</key>            <string>BlindSpot</string>
  <key>CFBundleDisplayName</key>     <string>BlindSpot</string>
  <key>CFBundleVersion</key>         <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleIconFile</key>        <string>BlindSpot</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSAccessibilityUsageDescription</key>
  <string>BlindSpot reads your selected text to answer AI questions. It never accesses content you haven't selected.</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

echo ""
echo "✓ Built: $(pwd)/$APP"
echo ""
echo "To install: drag BlindSpot.app to /Applications"
echo "To run:     open BlindSpot.app"
echo ""
echo "First launch: macOS may show a security warning."
echo "Go to System Settings → Privacy & Security → Open Anyway."
