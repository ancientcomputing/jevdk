#!/usr/bin/env bash
set -euo pipefail

# release.sh — build both downloads for one version, signed and notarized, into dist/:
#   dist/JevDK-<VERSION>-arm64.dmg (+ .sha256)
#   dist/jev-serve-<VERSION>-arm64.zip (+ .sha256)
#
#   VERSION=0.2.0 APP_IDENTITY=<Developer ID name or SHA-1> KEYCHAIN_PROFILE=<notarytool profile> scripts/release.sh
#
# Runs jevdk/scripts/release_macos.sh and jev-serve/scripts/release_macos.sh (see their headers for
# options, e.g. NOTARIZE=0 for a local test), then prints the `gh release create` command to
# publish them. It doesn't publish anything itself.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VERSION:?Set VERSION=x.y.z}"
: "${APP_IDENTITY:?Set APP_IDENTITY (Developer ID name or SHA-1)}"
export VERSION APP_IDENTITY

if [[ "${NOTARIZE:-1}" == "0" ]]; then export NOTARIZE_APP=0 NOTARIZE_DMG=0; fi

echo "=== JevDK"
"$ROOT/jevdk/scripts/release_macos.sh"
echo "=== jev-serve"
"$ROOT/jev-serve/scripts/release_macos.sh"

mkdir -p "$ROOT/dist"
cp "$ROOT/jevdk/dist/JevDK-$VERSION-arm64.dmg"* "$ROOT/dist/"
cp "$ROOT/jev-serve/dist/jev-serve-$VERSION-arm64.zip"* "$ROOT/dist/"
echo
echo "Release files in $ROOT/dist:"
ls -1 "$ROOT/dist" | grep -- "$VERSION"
echo
echo "Publish (after committing and pushing):"
echo "  gh release create v$VERSION -R ancientcomputing/jevdk --title \"JevDK and jev-serve $VERSION\" \\"
echo "    dist/JevDK-$VERSION-arm64.dmg dist/JevDK-$VERSION-arm64.dmg.sha256 \\"
echo "    dist/jev-serve-$VERSION-arm64.zip dist/jev-serve-$VERSION-arm64.zip.sha256"
