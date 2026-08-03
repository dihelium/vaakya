#!/bin/bash
# Export only this project from its containing Git repository.

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT="${1:-}"
if [[ -z "$OUTPUT" ]]; then
  echo "usage: $0 OUTPUT_DIRECTORY" >&2
  exit 2
fi
if [[ -e "$OUTPUT" ]]; then
  echo "error: output path already exists: $OUTPUT" >&2
  exit 1
fi

GIT_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_DIR="$(pwd -P)"
PROJECT_PREFIX="${PROJECT_DIR#"$GIT_ROOT"/}"

if [[ -n "$(git status --porcelain -- "$PROJECT_PREFIX")" ]]; then
  echo "error: project has uncommitted changes. Commit the reviewed release state first." >&2
  exit 1
fi

mkdir -p "$OUTPUT"
git -C "$GIT_ROOT" archive "HEAD:$PROJECT_PREFIX" | tar -x -C "$OUTPUT"

echo "exported clean public tree to: $OUTPUT"
