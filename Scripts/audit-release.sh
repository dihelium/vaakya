#!/bin/bash
# Verify a built bundle and the project's runtime privacy invariants.

set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Vaakya.app"
if [[ ! -d "$APP" ]]; then
  echo "error: $APP is missing. Run make build first." >&2
  exit 1
fi

search_regex() {
  if command -v rg >/dev/null 2>&1; then
    rg "$@"
  else
    grep -RE "$@"
  fi
}

search_fixed() {
  if command -v rg >/dev/null 2>&1; then
    rg -F "$@"
  else
    grep -RF "$@"
  fi
}

search_stream_regex() {
  if command -v rg >/dev/null 2>&1; then
    rg "$@"
  else
    grep -E "$@"
  fi
}

if search_regex -n 'Sparkle|SUFeedURL|SUPublicEDKey|Sentry|Telemetry|Analytics' Sources Resources; then
  echo "error: updater, telemetry, or analytics symbol found" >&2
  exit 1
fi

while IFS= read -r source_file; do
  case "$source_file" in
    Sources/Vaakya/OpenAILensClient.swift|Sources/Vaakya/ArchiveAskService.swift) ;;
    *)
      echo "error: unexpected runtime networking outside the reviewed clients: $source_file" >&2
      exit 1
      ;;
  esac
done < <(search_regex -l 'URLSession|import Network|NWConnection|CFNetwork' Sources || true)

while IFS= read -r process_file; do
  if [[ "$process_file" != "Sources/Vaakya/CodexLensClient.swift" ]]; then
    echo "error: unexpected subprocess capability: $process_file" >&2
    exit 1
  fi
done < <(search_regex -l 'Process\(' Sources || true)

if search_regex -n -i 'bhargav|pure storage|macbook|/Users/' Sources Resources docs; then
  echo "error: personal or machine-specific release content found" >&2
  exit 1
fi

CONTEXT_FILES="$(find Sources/VaakyaCore/Resources/Context -type f | sort)"
if [[ "$CONTEXT_FILES" != "Sources/VaakyaCore/Resources/Context/interview_default.md" ]]; then
  echo "error: bundled context must contain only the reviewed generic default" >&2
  echo "$CONTEXT_FILES" >&2
  exit 1
fi

if ! search_regex -q 'var lensEgressEnabled: Bool = false' Sources/Vaakya/Config.swift \
  || ! search_regex -q 'var selectedLLMRunner: String = "local"' Sources/Vaakya/Config.swift; then
  echo "error: safe inference defaults are missing" >&2
  exit 1
fi

for invariant in \
  '"--ephemeral"' \
  '"--ignore-user-config"' \
  '"--ignore-rules"' \
  '"features.shell_tool=false"' \
  '"features.unified_exec=false"' \
  '"web_search=\"disabled\""' \
  '"project_doc_max_bytes=0"' \
  '"history.persistence=\"none\""' \
  '"memories.generate_memories=false"' \
  '"analytics.enabled=false"' \
  '"--sandbox", "read-only"'; do
  if ! search_fixed -q "$invariant" Sources/Vaakya/CodexLensClient.swift; then
    echo "error: Codex safety invariant missing: $invariant" >&2
    exit 1
  fi
done

if search_regex -n 'workspace-write|danger-full-access|--full-auto|dangerously-bypass' Sources/Vaakya/CodexLensClient.swift; then
  echo "error: unsafe Codex execution mode found" >&2
  exit 1
fi

if search_regex -n 'security find-identity|VAAKYA_SKIP_INSTALL|/Applications' Scripts/build.sh Scripts/bundle.sh Makefile; then
  echo "error: build must not auto-select identities or install applications" >&2
  exit 1
fi

if search_regex -n 'notarytool|VAAKYA_NOTARY_PROFILE|security find-identity' Scripts/release-community.sh; then
  echo "error: community release must not use Apple signing or notarization credentials" >&2
  exit 1
fi
if ! search_fixed -q 'VAAKYA_CODESIGN_IDENTITY=-' Scripts/release-community.sh; then
  echo "error: community release must explicitly select ad-hoc signing" >&2
  exit 1
fi

if strings "$APP/Contents/MacOS/Vaakya" | search_stream_regex -n -i 'bhargav|pure storage|macbook|/Users/'; then
  echo "error: personal or machine-specific content found in release executable" >&2
  exit 1
fi

if search_regex -n -i 'pure storage|macbook|/Users/' "$APP/Contents/Resources"; then
  echo "error: personal or machine-specific content found in release resources" >&2
  exit 1
fi

while IFS= read -r bundled_text; do
  if [[ "$bundled_text" == "$APP/Contents/Resources/LICENSE.txt" ]]; then
    continue
  fi
  if search_regex -n -i 'bhargav' "$bundled_text"; then
    echo "error: personal name found outside the required license attribution" >&2
    exit 1
  fi
done < <(find "$APP/Contents/Resources" -type f | sort)

while IFS= read -r source_resource; do
  relative_resource="${source_resource#Sources/VaakyaCore/Resources/}"
  bundled_resource="$APP/Contents/Resources/$relative_resource"
  if [[ ! -f "$bundled_resource" ]] || ! cmp -s "$source_resource" "$bundled_resource"; then
    echo "error: bundled lens resource is missing or changed: $relative_resource" >&2
    exit 1
  fi
done < <(find Sources/VaakyaCore/Resources -type f | sort)

if plutil -p "$APP/Contents/Info.plist" | search_stream_regex -n 'SUFeedURL|SUPublicEDKey'; then
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

if [[ "$IDENTIFIER" != "io.github.dihelium.vaakya" ]]; then
  echo "error: unexpected bundle identifier: $IDENTIFIER" >&2
  exit 1
fi

echo "release audit OK"
echo "version: $VERSION"
echo "bundle identifier: $IDENTIFIER"
file "$APP/Contents/MacOS/Vaakya"
