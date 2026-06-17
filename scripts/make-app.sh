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

# SPM resource bundle — lives inside Contents/Resources so codesign covers it.
# ProviderIcon uses Bundle.resourcesBundle which checks resourceURL first.
cp -R "$BUILD_PATH/BlindSpot_BlindSpot.bundle" "$APP/Contents/Resources/"

# Bundle Sparkle.framework so the app can launch and check for updates.
# The binary links against @rpath/Sparkle.framework with rpath set to
# @executable_path/../lib, so framework goes in Contents/lib/.
mkdir -p "$APP/Contents/lib"
cp -R "$BUILD_PATH/Sparkle.framework" "$APP/Contents/lib/"

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
  <key>SUPublicEDKey</key>
  <string>UP9yKSlzPYGk1OTENgKcPD3+vMETH70FbFHYYrTk9Yo=</string>
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/Nainounen/blind-spot/main/appcast.xml</string>
</dict>
</plist>
PLIST

# Sign the bundle. This must happen AFTER Info.plist is written, since
# codesign covers it.
#
# If SIGN_IDENTITY is set (e.g. "Developer ID Application: Name (TEAMID)"),
# produce a real, notarization-ready signature: hardened runtime + secure
# timestamp + entitlements, signing nested code inner-to-outer. Otherwise
# fall back to an ad-hoc signature so local `swift build` workflows keep
# working without an Apple certificate.
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ENTITLEMENTS="BlindSpot.entitlements"
SPARKLE="$APP/Contents/lib/Sparkle.framework"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signing with Developer ID: $SIGN_IDENTITY"
    sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$@"; }

    # Nested Sparkle code first (inner → outer). The .app last covers everything.
    sign "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    sign "$SPARKLE/Versions/B/Autoupdate"
    sign "$SPARKLE/Versions/B/Updater.app"
    sign "$SPARKLE"
    sign --entitlements "$ENTITLEMENTS" "$APP"

    echo "  ✓ Developer ID signed $APP"
    codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 || \
        echo "  ⚠ codesign verification reported issues" >&2
else
    echo "No SIGN_IDENTITY set — ad-hoc signing (local/dev build)."
    if codesign --force --deep --sign - "$APP" 2>&1; then
        echo "  ✓ Ad-hoc signed $APP"
    else
        echo "  ⚠ codesign failed — Sparkle updates may reject this build" >&2
    fi
fi

echo ""
echo "✓ Built: $(pwd)/$APP"
echo ""
echo "To install: drag BlindSpot.app to /Applications"
echo "To run:     open BlindSpot.app"
echo ""
echo "First launch: macOS may show a security warning."
echo "Go to System Settings → Privacy & Security → Open Anyway."
