#!/bin/bash
# Create ZIP and DMG artifacts from build/Vaakya.app.

set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Vaakya.app"
if [[ ! -d "$APP" ]]; then
  echo "error: $APP is missing. Run make build first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BASE="Vaakya-$VERSION-macOS"
ZIP="dist/$BASE.zip"
DMG="dist/$BASE.dmg"
CHECKSUMS="dist/Vaakya-$VERSION-SHA256SUMS.txt"

mkdir -p dist
rm -f "$ZIP" "$DMG" "$CHECKSUMS"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/vaakya-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/Vaakya.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Vaakya $VERSION" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$DMG"

APP_AUTHORITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
if [[ "$APP_AUTHORITY" == Developer\ ID\ Application:* ]]; then
  codesign --force --sign "$APP_AUTHORITY" --timestamp "$DMG"
fi

shasum -a 256 "$DMG" "$ZIP" > "$CHECKSUMS"

echo "created: $DMG"
echo "created: $ZIP"
echo "created: $CHECKSUMS"
