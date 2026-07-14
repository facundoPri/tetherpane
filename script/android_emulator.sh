#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

AVD_NAME="AirDroidApi36"
IMAGE_PACKAGE="system-images;android-36;google_apis;arm64-v8a"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "usage: $0" >&2
  exit 0
fi

export_android_environment
adb="$(resolve_adb)" || {
  echo "ADB is unavailable. Install platform-tools or set ADB_PATH." >&2
  exit 1
}
avdmanager="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager"
if [[ ! -x "$avdmanager" ]]; then
  avdmanager="$(command -v avdmanager || true)"
fi
emulator="$ANDROID_SDK_ROOT/emulator/emulator"
launch_label="com.facundopri.airdroid.emulator"
emulator_log="${TMPDIR:-/tmp}/$AVD_NAME.log"
emulator_error_log="${TMPDIR:-/tmp}/$AVD_NAME.error.log"

if [[ -z "$avdmanager" || ! -x "$emulator" ]]; then
  echo "Android emulator tools are unavailable. Run make bootstrap." >&2
  exit 1
fi

if [[ ! -d "$ANDROID_SDK_ROOT/system-images/android-36/google_apis/arm64-v8a" ]]; then
  echo "The API 36 Google APIs ARM system image is unavailable. Run make bootstrap interactively." >&2
  exit 1
fi

if ! "$avdmanager" list avd | grep -Fq "Name: $AVD_NAME"; then
  printf 'no\n' | "$avdmanager" create avd --force --name "$AVD_NAME" --package "$IMAGE_PACKAGE" --device "pixel_7"
fi

find_running_serial() {
  local candidate
  while IFS= read -r candidate; do
    if [[ "$("$adb" -s "$candidate" shell getprop ro.boot.qemu.avd_name 2>/dev/null | tr -d '\r')" == "$AVD_NAME" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <("$adb" devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" { print $1 }')
  return 1
}

serial="$(find_running_serial || true)"
if [[ -z "$serial" ]]; then
  if command -v launchctl >/dev/null 2>&1; then
    launchctl remove "$launch_label" >/dev/null 2>&1 || true
    launchctl submit \
      -l "$launch_label" \
      -o "$emulator_log" \
      -e "$emulator_error_log" \
      -- "$emulator" "@$AVD_NAME" -no-snapshot -no-boot-anim
    emulator_process="launchd job $launch_label"
  else
    nohup "$emulator" "@$AVD_NAME" -no-snapshot -no-boot-anim >"$emulator_log" 2>"$emulator_error_log" < /dev/null &
    emulator_process="pid $!"
  fi
fi

for _ in $(seq 1 30); do
  serial="$(find_running_serial || true)"
  [[ -n "$serial" ]] && break
  sleep 2
done

if [[ -z "$serial" ]]; then
  echo "Emulator did not connect within 60 seconds. See $emulator_log and $emulator_error_log ($emulator_process)." >&2
  exit 1
fi

"$adb" -s "$serial" wait-for-device
for _ in $(seq 1 30); do
  [[ "$("$adb" -s "$serial" shell getprop sys.boot_completed | tr -d '\r')" == "1" ]] && break
  sleep 2
done

if [[ "$("$adb" -s "$serial" shell getprop sys.boot_completed | tr -d '\r')" != "1" ]]; then
  echo "Emulator connected but did not finish booting. See $emulator_log and $emulator_error_log." >&2
  exit 1
fi

if [[ "$("$adb" -s "$serial" shell settings get global development_settings_enabled | tr -d '\r')" != "1" ]]; then
  "$adb" -s "$serial" shell settings put global development_settings_enabled 1
  echo "Enabled Developer options in the disposable emulator for the onboarding QA path."
fi

printf 'Android emulator ready: %s\n' "$serial"
printf 'Run: make android-qa SERIAL=%s\n' "$serial"
