#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=macos_bundle_metadata.sh
source "$ROOT_DIR/script/macos_bundle_metadata.sh"
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tetherpane-macos-release.XXXXXX")"
VERSION="0.1.0"
BUILD_NUMBER="1"
ARCHITECTURE="${ARCHITECTURE:-native}"
APP_BUNDLE="$OUTPUT_DIR/$MACOS_APP_EXECUTABLE.app"
ARCHIVE="$OUTPUT_DIR/$MACOS_APP_EXECUTABLE-$VERSION-macos.zip"

cleanup() {
  rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/script/package_macos.sh" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --architecture "$ARCHITECTURE" \
  --sign - \
  --output-dir "$OUTPUT_DIR"

[[ -f "$ARCHIVE" ]] || {
  echo "Release archive is missing: $ARCHIVE" >&2
  exit 1
}

/usr/bin/ditto -x -k "$ARCHIVE" "$OUTPUT_DIR/unpacked"
"$ROOT_DIR/script/verify_macos_bundle.sh" \
  --app "$OUTPUT_DIR/unpacked/$MACOS_APP_EXECUTABLE.app" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --signature ad-hoc \
  --architecture "$ARCHITECTURE"

echo "PASS: macOS release command produces a versioned, hardened, verifiable app archive"
