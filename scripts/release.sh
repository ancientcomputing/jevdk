#!/usr/bin/env bash
set -euo pipefail

# release.sh — build the JevDK download for one version, signed, notarized and stapled, into dist/:
#   dist/JevDK-<VERSION>-arm64.dmg (+ .sha256)
# JevDK.app carries jev-serve (Contents/MacOS/jev-serve; JevDK → Install jev-serve Command… puts it
# on the PATH), so this one download is both tools and runs without Gatekeeper prompts.
#
#   VERSION=0.2.0 APP_IDENTITY=<Developer ID name or SHA-1> KEYCHAIN_PROFILE=<notarytool profile> scripts/release.sh
#
# ZIP=1 also builds the standalone jev-serve zip (dist/jev-serve-<VERSION>-arm64.zip) for scripts
# and CI: download it with curl, which doesn't quarantine it (from a browser, its loose frameworks
# can't carry a notarization ticket and macOS blocks them). NOTARIZE=0 for a local, signed-only test.
# It prints the `gh release create` command; it doesn't publish anything itself.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VERSION:?Set VERSION=x.y.z}"
: "${APP_IDENTITY:?Set APP_IDENTITY (Developer ID name or SHA-1)}"
export VERSION APP_IDENTITY
if [[ "${NOTARIZE:-1}" == "0" ]]; then export NOTARIZE_APP=0 NOTARIZE_DMG=0; fi

echo "=== JevDK (with jev-serve inside)"
"$ROOT/jevdk/scripts/release_macos.sh"
mkdir -p "$ROOT/dist"
cp "$ROOT/jevdk/dist/JevDK-$VERSION-arm64.dmg"* "$ROOT/dist/"
FILES="dist/JevDK-$VERSION-arm64.dmg dist/JevDK-$VERSION-arm64.dmg.sha256"

if [[ "${ZIP:-0}" == "1" ]]; then
  echo "=== jev-serve zip"
  "$ROOT/jev-serve/scripts/release_macos.sh"
  cp "$ROOT/jev-serve/dist/jev-serve-$VERSION-arm64.zip"* "$ROOT/dist/"
  FILES="$FILES dist/jev-serve-$VERSION-arm64.zip dist/jev-serve-$VERSION-arm64.zip.sha256"
fi

echo
echo "Release files in $ROOT/dist:"
ls -1 "$ROOT/dist" | grep -- "$VERSION"
echo
echo "Publish (after committing and pushing):"
echo "  gh release create $VERSION -R ancientcomputing/jevdk --title \"JevDK $VERSION\" $FILES"
echo "Or replace the files on an existing release:"
echo "  gh release upload $VERSION -R ancientcomputing/jevdk --clobber $FILES"
