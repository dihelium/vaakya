#!/bin/bash
# Install the already-built app for the current user and open it.

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE_APP="build/Vaakya.app"
INSTALL_DIR="${HOME}/Applications"
INSTALL_APP="${INSTALL_DIR}/Vaakya.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: $SOURCE_APP is missing. Run make build first." >&2
  exit 1
fi

if [[ -e "$INSTALL_APP" ]]; then
  echo "error: $INSTALL_APP already exists." >&2
  echo "Move the existing app aside, then run make install again." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
ditto "$SOURCE_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

echo "installed: $INSTALL_APP"
open "$INSTALL_APP"
