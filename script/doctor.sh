#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

heading() { printf '\n%s\n' "== $1 =="; }
report_missing() { printf 'missing (%s)\n' "$1"; }

heading "macOS and Swift"
sw_vers 2>/dev/null || report_missing "sw_vers"
if command -v swift >/dev/null 2>&1; then
  swift --version | head -n 2
else
  report_missing "swift"
fi

heading "Android build prerequisites"
if java_home="$(resolve_java_home 2>/dev/null)"; then
  printf 'JDK 17: %s\n' "$java_home"
  "$java_home/bin/java" -version 2>&1 | head -n 1
else
  report_missing "JDK 17; run make bootstrap"
fi
if sdkmanager="$(resolve_sdkmanager 2>/dev/null)"; then
  printf 'sdkmanager: %s\n' "$sdkmanager"
else
  report_missing "Android command-line tools; run make bootstrap"
fi
sdk_root="$(resolve_android_sdk_root)"
if [[ -d "$sdk_root" ]]; then
  printf 'Android SDK root: %s\n' "$sdk_root"
  [[ -d "$sdk_root/platforms/android-36" ]] && echo 'platforms;android-36: installed' || echo 'platforms;android-36: missing'
  [[ -d "$sdk_root/build-tools/36.0.0" ]] && echo 'build-tools;36.0.0: installed' || echo 'build-tools;36.0.0: missing'
  [[ -d "$sdk_root/system-images/android-36/google_apis/arm64-v8a" ]] && echo 'system-images;android-36;google_apis;arm64-v8a: installed' || echo 'system-images;android-36;google_apis;arm64-v8a: missing'
  [[ -d "$sdk_root/licenses" && -n "$(find "$sdk_root/licenses" -type f -maxdepth 1 -print -quit 2>/dev/null)" ]] && echo 'Android SDK license records: present' || echo 'Android SDK license records: missing; run make bootstrap interactively'
else
  printf 'Android SDK root: missing (%s)\n' "$sdk_root"
fi

heading "ADB devices"
if adb="$(resolve_adb 2>/dev/null)"; then
  printf 'ADB: %s\n' "$adb"
  "$adb" version | head -n 2
  "$adb" devices -l
  echo 'mDNS pairing services:'
  "$adb" mdns services || true
else
  report_missing "adb"
fi

heading "scrcpy"
if scrcpy="$(resolve_scrcpy 2>/dev/null)"; then
  printf 'scrcpy: %s\n' "$scrcpy"
  "$scrcpy" --version | head -n 1
else
  report_missing "scrcpy"
fi

heading "status"
echo "This command is read-only. Missing Android packages or licenses: run make bootstrap in an interactive terminal."
