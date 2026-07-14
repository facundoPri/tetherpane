#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PACKAGE_NAME="com.facundopri.airdroid.companion"
SERIAL=""

usage() {
  echo "usage: $0 [--serial <authorized-adb-serial>]" >&2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --serial)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      SERIAL="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

adb="$(resolve_adb)" || {
  echo "ADB is unavailable. Install platform-tools or set ADB_PATH." >&2
  exit 1
}
serial="$(require_exact_authorized_device "$adb" "$SERIAL")"

"$SCRIPT_DIR/android_gradle.sh" :app:assembleDebug --console=plain

apk="$ROOT_DIR/apps/android/app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -f "$apk" ]]; then
  echo "Debug APK was not produced at $apk." >&2
  exit 1
fi

"$adb" -s "$serial" install -r "$apk"
component="$("$adb" -s "$serial" shell cmd package resolve-activity --brief "$PACKAGE_NAME" | tr -d '\r' | tail -n 1)"
if [[ "$component" != */* ]]; then
  echo "Could not resolve the companion launcher activity for $PACKAGE_NAME." >&2
  exit 1
fi

"$adb" -s "$serial" shell am start -W -n "$component"
printf 'Installed and launched %s on %s\n' "$PACKAGE_NAME" "$serial"
