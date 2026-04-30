#!/bin/zsh
# Builds BlindSpot.app and packages it as a .dmg suitable for direct download
# from GitHub Releases (drag-to-Applications install UI) and for the Homebrew
# Cask.
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
    echo "Usage: ./make-release.sh <version>" >&2
    echo "       ./make-release.sh 1.0.1"     >&2
    exit 1
fi

DIST="dist"
APP="BlindSpot.app"
DMG="$DIST/BlindSpot-${VERSION}.dmg"
STAGING="$DIST/.dmg-staging"
VOLNAME="BlindSpot ${VERSION}"

# 1. Build the universal .app bundle with the right CFBundleVersion baked in.
./make-app.sh "$VERSION"

# 2. Lay out the DMG contents: the app on the left, an Applications symlink
#    on the right. When the user mounts the DMG, Finder shows both side by
#    side and they drag the app over — the standard macOS install gesture.
mkdir -p "$DIST"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 3. Build the compressed DMG (UDZO = standard zlib-compressed read-only).
rm -f "$DMG"
hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

rm -rf "$STAGING"

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
echo "  2. gh release create v${VERSION} $DMG --notes 'BlindSpot ${VERSION}'"
echo "  3. Update Casks/blindspot.rb in the homebrew-blindspot tap with"
echo "     version \"${VERSION}\" and sha256 \"${SHA256}\"."
echo ""
echo "  (Or skip 2 + 3 — the GitHub Actions workflow on tag push does both.)"
