#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=macos_bundle_metadata.sh
source "$ROOT_DIR/script/macos_bundle_metadata.sh"
APP_NAME="$MACOS_APP_EXECUTABLE"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

"$ROOT_DIR/script/package_macos.sh" \
  --configuration debug \
  --version 0.1.0 \
  --build-number 1 \
  --architecture native \
  --sign - \
  --output-dir "$DIST_DIR" \
  --skip-archive

BUNDLE_ID="$MACOS_BUNDLE_IDENTIFIER"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    DEBUG_BINARY="$(swift build -c debug --show-bin-path)/$APP_NAME"
    lldb -- "$DEBUG_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
