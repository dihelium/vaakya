#!/bin/bash
# Build, sign, notarize, package, and verify a public release.

set -euo pipefail

cd "$(dirname "$0")/.."

EXPECTED_VERSION="${1:-}"
IDENTITY="${VAAKYA_CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${VAAKYA_NOTARY_PROFILE:-}"

if [[ -z "$EXPECTED_VERSION" || -z "$IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
  echo "usage: VAAKYA_CODESIGN_IDENTITY='Developer ID Application: ...' VAAKYA_NOTARY_PROFILE='profile' $0 VERSION" >&2
  exit 2
fi

if [[ "$IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "error: a Developer ID Application identity is required" >&2
  exit 1
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ "$PLIST_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "error: requested version $EXPECTED_VERSION does not match Info.plist $PLIST_VERSION" >&2
  exit 1
fi

SWIFTPM_DISABLE_SANDBOX=1 make test
SWIFTPM_DISABLE_SANDBOX=1 Scripts/build.sh --release
Scripts/audit-release.sh

APP="build/Vaakya.app"
SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
  echo "error: app is not signed with Developer ID Application" >&2
  exit 1
fi

NOTARY_ZIP="build/Vaakya-notary.zip"
rm -f "$NOTARY_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

Scripts/package.sh

DMG="dist/Vaakya-$EXPECTED_VERSION-macOS.dmg"
ZIP="dist/Vaakya-$EXPECTED_VERSION-macOS.zip"
CHECKSUMS="dist/Vaakya-$EXPECTED_VERSION-SHA256SUMS.txt"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

spctl --assess --type execute --verbose=4 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
shasum -a 256 "$DMG" "$ZIP" > "$CHECKSUMS"

echo "public release gate passed"
echo "artifacts are in dist/"
