#!/bin/zsh
# Creates BlindSpot.app in the current directory.
# Usage: ./make-app.sh [version]

set -e
cd "$(git rev-parse --show-toplevel)"

VERSION="${1:-1.0.0}"
APP="BlindSpot.app"

echo "Building BlindSpot $VERSION…"
# Universal binary so Intel Macs (x86_64) and Apple Silicon (arm64) both work
# from the same .app bundle.
swift build -c release --arch arm64 --arch x86_64 2>&1
BUILD_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

# Generate icon if ICNS doesn't exist yet
if [[ ! -f "assets/BlindSpot.icns" ]]; then
    echo "Generating app icon…"
    swift scripts/make-icon.swift
fi

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BUILD_PATH/BlindSpot" "$APP/Contents/MacOS/BlindSpot"
cp assets/BlindSpot.icns "$APP/Contents/Resources/BlindSpot.icns"

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

# Ad-hoc sign the bundle so macOS treats it as a coherent code-signed unit.
# This must happen AFTER Info.plist is written, since codesign covers it.
# (Real Developer ID signing would happen later if an Apple cert is added.)
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo ""
echo "✓ Built: $(pwd)/$APP"
echo ""
echo "To install: drag BlindSpot.app to /Applications"
echo "To run:     open BlindSpot.app"
echo ""
echo "First launch: macOS may show a security warning."
echo "Go to System Settings → Privacy & Security → Open Anyway."
