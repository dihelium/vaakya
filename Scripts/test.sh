#!/bin/bash
# test.sh — run the Vaakya test suite.
#
# CLT-only machines (no Xcode) ship Swift Testing but not XCTest, and put
# Testing.framework in a non-standard path. This wrapper supplies the framework
# search path and runtime rpaths so `swift test` works on this machine.
# On a machine with Xcode installed, plain `swift test` also works.
#
# If your shell blocks SwiftPM's sandbox, opt out explicitly with
#   SWIFTPM_DISABLE_SANDBOX=1 Scripts/test.sh

set -euo pipefail
cd "$(dirname "$0")/.."

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"

if [[ "$ACTIVE_DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" && -d "$CLT_FRAMEWORKS" ]]; then
  EXTRA=( -Xswiftc "-F$CLT_FRAMEWORKS"
          -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
          -Xlinker -rpath -Xlinker "$CLT_LIBS" )
  if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    swift test --disable-sandbox "${EXTRA[@]}"
  else
    swift test "${EXTRA[@]}"
  fi
else
  if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
    swift test --disable-sandbox
  else
    swift test
  fi
fi
