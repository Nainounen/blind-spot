#!/bin/zsh
# Builds BlindSpot.app and packages it as a release zip suitable for a
# GitHub Release + Homebrew Cask.
#
# Usage: ./make-release.sh <version>
#        ./make-release.sh 1.0.1
#
# Output:
#   dist/BlindSpot-<version>.zip
#   dist/BlindSpot-<version>.zip.sha256

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
ZIP="$DIST/BlindSpot-${VERSION}.zip"

# 1. Build the .app bundle with the right CFBundleVersion baked in.
./make-app.sh "$VERSION"

# 2. Re-zip with `ditto` so resource forks and symlinks survive — what every
#    macOS distribution flow uses. `zip` mangles them, breaking codesign.
mkdir -p "$DIST"
rm -f "$ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# 3. Compute sha256 — needed for the Cask formula.
SHA256=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA256  $(basename "$ZIP")" > "$ZIP.sha256"

echo ""
BYTES=$(stat -f %z "$ZIP")
echo "✓ Release artifact: $ZIP"
awk -v b="$BYTES" 'BEGIN{ split("B KB MB GB", u); s=b; i=1; while(s>1024 && i<4){s/=1024;i++} printf "  size:    %.1f %s (%d bytes)\n", s, u[i], b }'
echo "  sha256:  $SHA256"
echo ""
echo "Next steps:"
echo "  1. git tag v${VERSION} && git push origin v${VERSION}"
echo "  2. gh release create v${VERSION} $ZIP --notes 'BlindSpot ${VERSION}'"
echo "  3. Update Casks/blindspot.rb in the homebrew-blindspot tap with"
echo "     version \"${VERSION}\" and sha256 \"${SHA256}\"."
echo ""
echo "  (Or skip 2 + 3 — the GitHub Actions workflow on tag push does both.)"
