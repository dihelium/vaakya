#!/bin/bash
# Install the built app for the current user and open it.

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE_APP="build/Vaakya.app"
INSTALL_DIR="${VAAKYA_INSTALL_DIR:-${HOME}/Applications}"
INSTALL_APP="${INSTALL_DIR}/Vaakya.app"
BUNDLE_ID="io.github.dihelium.vaakya"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: $SOURCE_APP is missing. Run make build first." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
STAGING_ROOT="$(mktemp -d "${INSTALL_DIR}/.vaakya-install.XXXXXX")"
STAGED_APP="${STAGING_ROOT}/Vaakya.app"
trap 'rm -rf "$STAGING_ROOT"' EXIT

ditto "$SOURCE_APP" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

if pgrep -xq Vaakya 2>/dev/null; then
  osascript -e "tell application id \"${BUNDLE_ID}\" to quit" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    pgrep -xq Vaakya 2>/dev/null || break
    sleep 0.4
  done
  if pgrep -xq Vaakya 2>/dev/null; then
    echo "error: Vaakya is still running. Quit it and run make install again." >&2
    exit 1
  fi
fi

if [[ -e "$INSTALL_APP" ]]; then
  BACKUP_APP="${INSTALL_APP}.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$INSTALL_APP" "$BACKUP_APP"
  echo "previous app kept at: $BACKUP_APP"
fi

mv "$STAGED_APP" "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

echo "installed: $INSTALL_APP"
open "$INSTALL_APP"
