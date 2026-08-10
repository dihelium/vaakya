#!/bin/bash
# Assemble Vaakya.app from a SwiftPM binary.
#
# Signing is ad-hoc by default. A Developer ID identity is used only when the
# caller explicitly supplies VAAKYA_CODESIGN_IDENTITY.

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
case "$CONFIG" in
  --debug|debug) CONFIG="debug" ;;
  --release|release) CONFIG="release" ;;
  *) echo "usage: $0 [--debug|--release]" >&2; exit 2 ;;
esac

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
APP_DIR="build/Vaakya.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BIN=".build/$CONFIG/Vaakya"

if [[ ! -f "$BIN" ]]; then
  echo "error: binary not found at $BIN. Run Scripts/build.sh first." >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES/ThirdPartyLicenses"

cp "$BIN" "$MACOS/Vaakya"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp LICENSE "$RESOURCES/LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$RESOURCES/THIRD_PARTY_NOTICES.md"

if [[ -f .build/checkouts/FluidAudio/LICENSE ]]; then
  cp .build/checkouts/FluidAudio/LICENSE "$RESOURCES/ThirdPartyLicenses/FluidAudio-Apache-2.0.txt"
fi
if [[ -f Resources/vaakya.icns ]]; then
  cp Resources/vaakya.icns "$RESOURCES/vaakya.icns"
else
  echo "note: Resources/vaakya.icns is not present. Bundling without a custom icon."
fi

IDENTITY="${VAAKYA_CODESIGN_IDENTITY:--}"

SIGN_ARGS=(
  --force
  --sign "$IDENTITY"
  --identifier "$BUNDLE_ID"
  --options runtime
  --entitlements Resources/Vaakya.entitlements
)
if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  SIGN_ARGS+=(--timestamp)
fi

# The audio-input entitlement is required before TCC can show the mic prompt
# when hardened runtime is enabled.
codesign "${SIGN_ARGS[@]}" "$APP_DIR"

if [[ "$IDENTITY" == "-" ]]; then
  echo "warning: no signing identity found. The app is ad-hoc signed."
  echo "         Gatekeeper will block public distribution and TCC grants may reset."
else
  echo "signed $APP_DIR with identity: $IDENTITY"
fi

codesign --verify --deep --strict "$APP_DIR"
echo "codesign verify OK"
echo "built: $APP_DIR"
