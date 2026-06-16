#!/bin/zsh
# Generates or updates appcast.xml after a release DMG is built.
# Run this locally after ./make-release.sh, then commit + push appcast.xml.
#
# Usage: ./scripts/update-appcast.sh <version>
#        ./scripts/update-appcast.sh 1.0.9
#
# Requires the Sparkle private key in your macOS Keychain (put there by
# generate_keys the first time Sparkle was set up).

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    if [[ -f VERSION ]]; then
        VERSION=$(tr -d '[:space:]' < VERSION)
    else
        echo "Usage: ./scripts/update-appcast.sh <version>" >&2
        exit 1
    fi
fi

DMG="dist/BlindSpot-${VERSION}.dmg"
if [[ ! -f "$DMG" ]]; then
    echo "Error: $DMG not found. Run ./scripts/make-release.sh first." >&2
    exit 1
fi

SPARKLE_TOOLS=".build/artifacts/sparkle/Sparkle/bin"
if [[ ! -f "$SPARKLE_TOOLS/generate_appcast" ]]; then
    echo "Resolving Sparkle tools…"
    swift package resolve
fi

"$SPARKLE_TOOLS/generate_appcast" \
    --link "https://github.com/Nainounen/blind-spot/releases" \
    dist/

echo ""
echo "✓ appcast.xml updated."
echo ""
echo "Next: commit and push appcast.xml"
echo "  git add appcast.xml && git commit -m 'chore: update appcast for v${VERSION}' && git push"
