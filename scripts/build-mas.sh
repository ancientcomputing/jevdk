#!/usr/bin/env bash
set -euo pipefail

# build-mas.sh — the Mac App Store build of JevDK (docs/mas-plan.md). Two signing modes:
#
#   MAS_SIGN=dev (default)  Apple Development identity, no provisioning profile. Sandboxed and
#                           runnable on this Mac — for testing the App Sandbox locally.
#   MAS_SIGN=store          Apple Distribution identity + the Mac App Store provisioning profile,
#                           then a .pkg signed with the installer identity, for Transporter /
#                           TestFlight. A distribution-signed app does not launch locally.
#
#   VERSION=1.0.0 MAS_SIGN=store scripts/build-mas.sh
#
# Differs from the DMG build (scripts/release.sh, which is unaffected):
#   - compiled with MAS_BUILD: no jev-serve installer (JevDK → Get jev-serve… opens its download
#     page), and turning on a hosted backend asks before any text is sent to it;
#   - DMG-only features compiled out (guideline 2.5.19: no hidden, dormant or undocumented
#     features): the command-line modes (--check, --check-remote, --csv, --write-iconset), the free
#     Featherless demo, and API keys from environment variables. The build fails if any is left;
#   - no jev-serve inside the app (a sandboxed copy couldn't run from the PATH);
#   - sandboxed (scripts/mas/JevDK.entitlements); models are downloaded into the app's container,
#     not the shared ~/.cache/huggingface;
#   - its own bundle ID, so both builds can be installed side by side.
#
# Environment:
#   VERSION                 CFBundleShortVersionString (required)
#   BUILD_NUMBER            CFBundleVersion; must increase on every upload (default: date-based)
#   APP_SIGN_IDENTITY       override the auto-detected signing identity
#   INSTALLER_SIGN_IDENTITY store mode: override the auto-detected installer identity
#   PROVISIONING_PROFILE    store mode: path to the profile (default: found by bundle ID)
#   OUT_DIR                 where the .app (and .pkg) go (default: dist/mas-<mode>)
#   TEST_BUNDLE_ID          dev mode only: another bundle ID, so the app starts in an empty container
#                           (first-launch testing), e.g. ai.thisbrain.jevdk.firstrun
#   DEVELOPER_DIR           Xcode 27 (default: xcode-select -p)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT="$ROOT/jevdk"
RES_SRC="$ROOT/scripts/mas"

APP_NAME="JevDK"
BUNDLE_ID="ai.thisbrain.jevdk"

: "${VERSION:?Set VERSION=x.y.z}"
MAS_SIGN="${MAS_SIGN:-dev}"
case "$MAS_SIGN" in
  dev|store) ;;
  *) echo "MAS_SIGN must be dev or store (got: $MAS_SIGN)" >&2; exit 1 ;;
esac
# Dev only: TEST_BUNDLE_ID gives the app another ID, and so a fresh, empty sandbox container
# (no models, no saved workspace) for testing a first launch. The store build always uses BUNDLE_ID.
if [[ -n "${TEST_BUNDLE_ID:-}" ]]; then
  [[ "$MAS_SIGN" == dev ]] || { echo "TEST_BUNDLE_ID is for MAS_SIGN=dev only." >&2; exit 1; }
  BUNDLE_ID="$TEST_BUNDLE_ID"
fi
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d.%H%M)}"
OUT_DIR="${OUT_DIR:-$ROOT/dist/mas-$MAS_SIGN}"
BUILD_DIR="$ROOT/build/mas"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR

APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Signing identities ---------------------------------------------------------------------

# The team (OU) of an installed signing certificate.
cert_team() {
  security find-certificate -c "$1" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU *= *([A-Z0-9]{10}).*/\1/p' | head -1
}

if [[ "$MAS_SIGN" == dev ]]; then
  APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -oE '"Apple Development:[^"]+"' | head -1 | tr -d '"')}"
  [[ -n "$APP_SIGN_IDENTITY" ]] || { echo "No Apple Development identity found (Xcode → Settings → Accounts → Manage Certificates)." >&2; exit 1; }
  TEAM_ID="$(cert_team "$APP_SIGN_IDENTITY")"
else
  INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-$(security find-identity -v | grep -oE '"(Mac Installer Distribution|3rd Party Mac Developer Installer):[^"]+"' | head -1 | tr -d '"')}"
  [[ -n "$INSTALLER_SIGN_IDENTITY" ]] || { echo "No Mac Installer Distribution identity found." >&2; exit 1; }

  PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  if [[ -z "${PROVISIONING_PROFILE:-}" ]]; then
    shopt -s nullglob
    for candidate in "$PROFILES_DIR"/*.provisionprofile; do
      decoded="$(security cms -D -i "$candidate" 2>/dev/null || true)"
      aid="$(plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -o - - <<<"$decoded" 2>/dev/null || true)"
      # A development profile for the same App ID (it lists devices) isn't for an upload.
      if plutil -extract ProvisionedDevices raw -o - - <<<"$decoded" >/dev/null 2>&1; then continue; fi
      if [[ "$aid" == *".$BUNDLE_ID" ]]; then PROVISIONING_PROFILE="$candidate"; break; fi
    done
    shopt -u nullglob
  fi
  [[ -n "${PROVISIONING_PROFILE:-}" && -f "$PROVISIONING_PROFILE" ]] || { echo "No Mac App Store provisioning profile for $BUNDLE_ID in $PROFILES_DIR." >&2; exit 1; }
  security cms -D -i "$PROVISIONING_PROFILE" > "$WORK_DIR/profile.plist"
  TEAM_ID="$(plutil -extract 'TeamIdentifier.0' raw -o - "$WORK_DIR/profile.plist")"
  APP_IDENTIFIER="$(plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -o - "$WORK_DIR/profile.plist")"
  [[ "$APP_IDENTIFIER" == "$TEAM_ID.$BUNDLE_ID" ]] || { echo "Profile is for $APP_IDENTIFIER, expected $TEAM_ID.$BUNDLE_ID" >&2; exit 1; }

  # Sign with the certificate the profile was made for, by SHA-1. App Store Connect rejects an app
  # whose signing certificate isn't in its profile (error 90284), and the portal lets a profile be
  # generated for an older "3rd Party Mac Developer Application" certificate as well as for the
  # current "Apple Distribution" one.
  PROFILE_CERTS=()
  count="$(plutil -extract DeveloperCertificates raw -o - "$WORK_DIR/profile.plist")"
  for ((i = 0; i < count; i++)); do
    plutil -extract "DeveloperCertificates.$i" raw -o - "$WORK_DIR/profile.plist" | base64 -d > "$WORK_DIR/cert.der"
    PROFILE_CERTS+=("$(shasum -a 1 "$WORK_DIR/cert.der" | cut -c1-40 | tr a-f A-F)")
  done
  KEYCHAIN_IDENTITIES="$(security find-identity -v -p codesigning)"
  if [[ -n "${APP_SIGN_IDENTITY:-}" ]]; then
    # A name or a SHA-1; either way it must be one of the profile's certificates.
    sha="$(grep -F "$APP_SIGN_IDENTITY" <<<"$KEYCHAIN_IDENTITIES" | awk '{print $2}' | head -1)"
    [[ " ${PROFILE_CERTS[*]} " == *" $sha "* ]] || { echo "APP_SIGN_IDENTITY isn't a certificate in $PROVISIONING_PROFILE." >&2; exit 1; }
    APP_SIGN_IDENTITY="$sha"
  else
    for sha in "${PROFILE_CERTS[@]}"; do
      if grep -q " $sha " <<<"$KEYCHAIN_IDENTITIES"; then APP_SIGN_IDENTITY="$sha"; break; fi
    done
  fi
  if [[ -z "${APP_SIGN_IDENTITY:-}" ]]; then
    echo "None of the certificates in $PROVISIONING_PROFILE is a signing identity in your keychain:" >&2
    for ((i = 0; i < count; i++)); do
      plutil -extract "DeveloperCertificates.$i" raw -o - "$WORK_DIR/profile.plist" | base64 -d \
        | openssl x509 -inform der -noout -subject 2>/dev/null | sed -nE 's/.*CN ?= ?([^,]+).*/  \1/p' >&2
    done
    echo "Regenerate the profile in the developer portal with your Apple Distribution certificate, download it, and run this again." >&2
    exit 1
  fi
fi
[[ -n "$TEAM_ID" ]] || { echo "Could not determine the team ID of $APP_SIGN_IDENTITY" >&2; exit 1; }
echo "Mode: $MAS_SIGN, version $VERSION ($BUILD_NUMBER)"
if [[ "$APP_SIGN_IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
  echo "Signing with: $(grep -F "$APP_SIGN_IDENTITY" <<<"$(security find-identity -v -p codesigning)" | head -1 | sed -E 's/.*"(.*)".*/\1/') ($APP_SIGN_IDENTITY)"
else
  echo "Signing with: $APP_SIGN_IDENTITY"
fi

# --- Build ----------------------------------------------------------------------------------

# Release, arm64, unsigned (signed below). MAS_BUILD is the only compilation condition.
echo "Archiving $APP_NAME (Release, arm64, MAS_BUILD)..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project "$APP_ROOT/JevDK.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -quiet

# --- Assemble -------------------------------------------------------------------------------

echo "Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$OUT_DIR"
ditto "$BUILD_DIR/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" "$APP_DIR"
mkdir -p "$RESOURCES_DIR"

# Info.plist: the store bundle ID and versions, plus what App Store Connect asks for.
PLIST="$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
# HTTPS only, standard system crypto — exempt; skips the export-compliance question on each upload.
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright © 2026 ThisBrainAI LLC. All rights reserved." "$PLIST"

# The app icon is drawn in code; render it into AppIcon.icns, as the DMG build does.
# The MAS binary has no command-line modes (guideline 2.5.19), so the icon is rendered by the
# command-line build of the same app (`swift build`, no MAS_BUILD), kept in its own scratch path.
echo "Rendering the app icon..."
ICON_SCRATCH="$ROOT/build/icon-tool"
swift build --package-path "$APP_ROOT" --scratch-path "$ICON_SCRATCH" --product "$APP_NAME" -q
"$(swift build --package-path "$APP_ROOT" --scratch-path "$ICON_SCRATCH" --show-bin-path)/$APP_NAME" \
  --write-iconset "$WORK_DIR/AppIcon.iconset"
iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$WORK_DIR/AppIcon.iconset"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST"

# Apache-2.0 §4(d): the SDK's NOTICE (it bundles the MLX stack).
cp "$ROOT/NOTICE" "$RESOURCES_DIR/NOTICE"
cp "$RES_SRC/PrivacyInfo.xcprivacy" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"

# SDK 2.0.0-GA only: its Inference framework's bundle ID is `mlx-swift_Cmlx`, which App Store Connect
# rejects (90277: not a valid bundle identifier). That SDK sets it so MLX finds default.metallib in
# the framework's Resources by bundle ID. Give it a valid ID like Core's and Remote's, and move
# mlx-swift_Cmlx.bundle into the app's own Resources instead: MLX looks in the main bundle for it
# first (device.cpp, load_swiftpm_library). Moved, not copied: two bundles with the same ID
# (mlx-swift.Cmlx.resources) in one app can be rejected too (90685). SDK 2.1.0-GA and later ship a
# valid ID (lab.locallm.sdk.inference) and need none of this.
INFERENCE_FW="$FRAMEWORKS_DIR/LocalLMLabSDKInference.framework"
INFERENCE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFERENCE_FW/Resources/Info.plist")"
if [[ "$INFERENCE_ID" == mlx-swift_Cmlx ]]; then
  echo "SDK 2.0.0-GA Inference framework: renaming its bundle ID and moving mlx-swift_Cmlx.bundle into the app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier lab.locallm.sdk.inference" "$INFERENCE_FW/Resources/Info.plist"
  mv "$INFERENCE_FW/Resources/mlx-swift_Cmlx.bundle" "$RESOURCES_DIR/mlx-swift_Cmlx.bundle"
fi

# The published xcframework zips carry AppleDouble/xattr detritus that breaks signing, and App
# Store Connect rejects any file carrying com.apple.quarantine (error 91109) — a browser-downloaded
# provisioning profile has it. Cleared before signing, since the signature seals the files.
find "$APP_DIR" -name '._*' -delete
xattr -cr "$APP_DIR"

# Guideline 2.5.19 (no hidden, dormant or undocumented features): the DMG-only parts are compiled out
# of the MAS build. Fail if any of them is still in the binary.
for marker in simple-jev-demo-api.featherless.ai FEATHERLESS_API_KEY OPENROUTER_API_KEY "Couldn't write the iconset"; do
  if strings "$CONTENTS_DIR/MacOS/$APP_NAME" | grep -qF "$marker"; then
    echo "The MAS binary still contains a DMG-only feature ($marker): check the #if MAS_BUILD gates." >&2; exit 1
  fi
done

# Every bundle ID in the app must be letters, digits, hyphens and dots (90277), and appear only once
# (90685), or the upload fails.
SEEN_IDS=""
while IFS= read -r plist; do
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  [[ -n "$id" ]] || continue
  if [[ ! "$id" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Invalid bundle identifier '$id' in ${plist#"$APP_DIR/"}" >&2; exit 1
  fi
  if [[ " $SEEN_IDS " == *" $id "* ]]; then
    echo "Bundle identifier '$id' appears more than once (again in ${plist#"$APP_DIR/"})" >&2; exit 1
  fi
  SEEN_IDS="$SEEN_IDS $id"
done < <(find "$APP_DIR" -name Info.plist)

# --- Entitlements ---------------------------------------------------------------------------

APP_ENTITLEMENTS="$WORK_DIR/app.entitlements"
cp "$RES_SRC/JevDK.entitlements" "$APP_ENTITLEMENTS"
if [[ "$MAS_SIGN" == store ]]; then
  # A manual codesign of a MAS build must carry these two from the profile (Xcode adds them
  # automatically); without them App Store Connect rejects the upload.
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" "$APP_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$APP_ENTITLEMENTS"
  cp "$PROVISIONING_PROFILE" "$CONTENTS_DIR/embedded.provisionprofile"
  xattr -c "$CONTENTS_DIR/embedded.provisionprofile"
fi

# --- Sign (inside out) ----------------------------------------------------------------------

sign() {
  codesign --force --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$@"
}

echo "Signing..."
shopt -s nullglob
FRAMEWORKS=("$FRAMEWORKS_DIR"/*.framework)
shopt -u nullglob
for fw in ${FRAMEWORKS[@]+"${FRAMEWORKS[@]}"}; do
  while IFS= read -r b; do sign "$b"; done < <(find "$fw" -depth -type d -name '*.bundle')
  sign "$fw/$(basename "$fw" .framework)"
  sign "$fw"
done
if [[ -d "$RESOURCES_DIR/mlx-swift_Cmlx.bundle" ]]; then sign "$RESOURCES_DIR/mlx-swift_Cmlx.bundle"; fi
sign --entitlements "$APP_ENTITLEMENTS" "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "App entitlements:"
codesign -d --entitlements - --xml "$APP_DIR" 2>/dev/null | plutil -p - | sed -E "s/$TEAM_ID/<team>/g"
if [[ -e "$CONTENTS_DIR/MacOS/jev-serve" ]]; then echo "jev-serve must not be in the MAS build" >&2; exit 1; fi

if [[ "$MAS_SIGN" == store ]]; then
  PKG_PATH="$OUT_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER.pkg"
  echo "Building $PKG_PATH..."
  rm -f "$PKG_PATH"
  productbuild --component "$APP_DIR" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$PKG_PATH"
  pkgutil --check-signature "$PKG_PATH" | head -3
  echo "Done: $PKG_PATH (upload with Transporter)"
else
  echo "Done: $APP_DIR"
  echo "  open \"$APP_DIR\""
fi
