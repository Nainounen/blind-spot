#!/bin/zsh
# Builds BlindSpot.app and packages it as a .dmg suitable for direct download
# from GitHub Releases (drag-to-Applications install UI) and for the Homebrew
# Cask.
#
# Requires: create-dmg  (brew install create-dmg)
#
# Usage: ./make-release.sh <version>
#        ./make-release.sh 1.0.1
#
# Output:
#   dist/BlindSpot-<version>.dmg
#   dist/BlindSpot-<version>.dmg.sha256

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    if [[ -f "VERSION" ]]; then
        VERSION=$(tr -d '[:space:]' < VERSION)
    else
        echo "Usage: ./make-release.sh <version>" >&2
        echo "       ./make-release.sh 1.0.1"     >&2
        exit 1
    fi
fi

if ! command -v create-dmg &>/dev/null; then
    echo "Error: create-dmg is not installed." >&2
    echo "       brew install create-dmg" >&2
    exit 1
fi

DIST="dist"
APP="BlindSpot.app"
DMG="$DIST/BlindSpot-${VERSION}.dmg"
VOLNAME="BlindSpot ${VERSION}"

# 1. Build the universal .app bundle with the right CFBundleVersion baked in.
./make-app.sh "$VERSION"

# 2. Generate the DMG background artwork used by Finder.
swift make-dmg-bg.swift

# 3. Package the app into a DMG with a drag-to-Applications layout.
#    create-dmg handles the Finder window cosmetics without needing AppleScript
#    or a running Finder, so this works identically locally and in CI.
mkdir -p "$DIST"
rm -f "$DMG"

create-dmg \
    --volname    "$VOLNAME" \
    --background "BlindSpot-dmg-bg.png" \
    --window-pos  200 120 \
    --window-size 600 400 \
    --icon-size   128 \
    --text-size   14 \
    --icon        "BlindSpot.app" 160 220 \
    --app-drop-link               440 220 \
    --hide-extension "BlindSpot.app" \
    "$DMG" \
    "$APP"

# 4. Compute sha256 — needed for the Cask formula.
SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "$SHA256  $(basename "$DMG")" > "$DMG.sha256"

echo ""
BYTES=$(stat -f %z "$DMG")
echo "✓ Release artifact: $DMG"
awk -v b="$BYTES" 'BEGIN{ split("B KB MB GB", u); s=b; i=1; while(s>1024 && i<4){s/=1024;i++} printf "  size:    %.1f %s (%d bytes)\n", s, u[i], b }'
echo "  sha256:  $SHA256"
echo ""
echo "Test the install UX locally:"
echo "  open $DMG     # mounts it; double-click in Finder to see drag layout"
echo ""
echo "Next steps:"
echo "  1. git tag v${VERSION} && git push origin v${VERSION}"
echo "  2. The GitHub Actions workflow triggers automatically and publishes the release."
echo ""
