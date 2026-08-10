#!/bin/bash
# Build and verify an ad-hoc-signed release without Apple credentials.

set -euo pipefail

cd "$(dirname "$0")/.."

EXPECTED_VERSION="${1:-}"
if [[ -z "$EXPECTED_VERSION" ]]; then
  echo "usage: $0 VERSION" >&2
  exit 2
fi

PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
if [[ "$PLIST_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "error: requested version $EXPECTED_VERSION does not match Info.plist $PLIST_VERSION" >&2
  exit 1
fi

make test
VAAKYA_CODESIGN_IDENTITY=- Scripts/build.sh --release
Scripts/audit-release.sh

APP="build/Vaakya.app"
SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$SIGNATURE" != *"Signature=adhoc"* ]]; then
  echo "error: community release must be ad-hoc signed" >&2
  exit 1
fi
if [[ "$SIGNATURE" == *"Authority="* ]]; then
  echo "error: community release unexpectedly contains a signing authority" >&2
  exit 1
fi

Scripts/package.sh

ZIP="dist/Vaakya-$EXPECTED_VERSION-macOS.zip"
DMG="dist/Vaakya-$EXPECTED_VERSION-macOS.dmg"
CHECKSUMS="dist/Vaakya-$EXPECTED_VERSION-SHA256SUMS.txt"

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vaakya-community-release.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Vaakya.app"

EXTRACTED_SIGNATURE="$(codesign -dvv "$VERIFY_DIR/Vaakya.app" 2>&1 || true)"
if [[ "$EXTRACTED_SIGNATURE" != *"Signature=adhoc"* ]]; then
  echo "error: packaged app did not preserve its ad-hoc signature" >&2
  exit 1
fi

(
  cd dist
  shasum -a 256 -c "$(basename "$CHECKSUMS")"
)

echo "community release gate passed"
echo "notarization: intentionally skipped"
echo "artifacts:"
echo "  $DMG"
echo "  $ZIP"
echo "  $CHECKSUMS"
