#!/bin/bash
# build.sh — build the Vaakya package and assemble + sign Vaakya.app.
#
# Usage: Scripts/build.sh [--debug|--release]   (default: release)
#
# NOTE: if your shell blocks SwiftPM's sandbox (sandbox-exec error), run with
#   SWIFTPM_DISABLE_SANDBOX=1 Scripts/build.sh

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
case "$CONFIG" in
  --debug|debug)  CONFIG="debug" ;;
  --release|release) CONFIG="release" ;;
  *) echo "usage: $0 [--debug|--release]" >&2; exit 2 ;;
esac
MODE="$CONFIG"

if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
  swift build -c "$MODE" --disable-sandbox
else
  swift build -c "$MODE"
fi
Scripts/bundle.sh "$CONFIG"
