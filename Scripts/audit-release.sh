#!/bin/bash
# Verify a built bundle and the project's runtime privacy invariants.

set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Vaakya.app"
if [[ ! -d "$APP" ]]; then
  echo "error: $APP is missing. Run make build first." >&2
  exit 1
fi

if rg -n 'URLSession|import Network|NWConnection|CFNetwork|Sparkle|SUFeedURL|SUPublicEDKey' Sources; then
  echo "error: runtime network or updater symbol found in Sources" >&2
  exit 1
fi

if plutil -p "$APP/Contents/Info.plist" | rg -n 'SUFeedURL|SUPublicEDKey'; then
  echo "error: updater key found in app Info.plist" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=4 "$APP"

ENTITLEMENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null)"
if [[ "$ENTITLEMENTS" != *"com.apple.security.device.audio-input"* ]]; then
  echo "error: signed app is missing the audio-input entitlement" >&2
  exit 1
fi

if [[ ! -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" ]]; then
  echo "error: third-party notices are missing from the app bundle" >&2
  exit 1
fi
if [[ ! -f "$APP/Contents/Resources/LICENSE.txt" ]]; then
  echo "error: project license is missing from the app bundle" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"

echo "release audit OK"
echo "version: $VERSION"
echo "bundle identifier: $IDENTIFIER"
file "$APP/Contents/MacOS/Vaakya"
