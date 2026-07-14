#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_adb() {
  if [[ -n "${ADB_PATH:-}" && -x "${ADB_PATH}" ]]; then
    printf '%s\n' "$ADB_PATH"
  elif [[ -x /opt/homebrew/bin/adb ]]; then
    printf '%s\n' /opt/homebrew/bin/adb
  elif command -v adb >/dev/null 2>&1; then
    command -v adb
  else
    return 1
  fi
}

resolve_scrcpy() {
  if [[ -n "${SCRCPY_PATH:-}" && -x "${SCRCPY_PATH}" ]]; then
    printf '%s\n' "$SCRCPY_PATH"
  elif [[ -x /opt/homebrew/bin/scrcpy ]]; then
    printf '%s\n' /opt/homebrew/bin/scrcpy
  elif command -v scrcpy >/dev/null 2>&1; then
    command -v scrcpy
  else
    return 1
  fi
}

resolve_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    printf '%s\n' "$JAVA_HOME"
  elif /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    /usr/libexec/java_home -v 17
  elif command -v brew >/dev/null 2>&1 && [[ -d "$(brew --prefix openjdk@17 2>/dev/null)/libexec/openjdk.jdk/Contents/Home" ]]; then
    printf '%s\n' "$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
  else
    return 1
  fi
}

resolve_sdkmanager() {
  if [[ -n "${SDKMANAGER_PATH:-}" && -x "${SDKMANAGER_PATH}" ]]; then
    printf '%s\n' "$SDKMANAGER_PATH"
  elif command -v sdkmanager >/dev/null 2>&1; then
    command -v sdkmanager
  elif [[ -x /opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager ]]; then
    printf '%s\n' /opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager
  elif [[ -x /usr/local/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager ]]; then
    printf '%s\n' /usr/local/share/android-commandlinetools/cmdline-tools/latest/bin/sdkmanager
  else
    return 1
  fi
}

resolve_android_sdk_root() {
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
  elif [[ -n "${ANDROID_HOME:-}" ]]; then
    printf '%s\n' "$ANDROID_HOME"
  else
    printf '%s\n' "$HOME/Library/Android/sdk"
  fi
}

export_android_environment() {
  local java_home
  java_home="$(resolve_java_home)" || {
    echo "JDK 17 is unavailable. Run 'make bootstrap' or set JAVA_HOME." >&2
    return 1
  }
  export JAVA_HOME="$java_home"
  export ANDROID_SDK_ROOT="$(resolve_android_sdk_root)"
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
  if [[ ! -d "$ANDROID_SDK_ROOT" ]]; then
    echo "Android SDK is unavailable at $ANDROID_SDK_ROOT. Run 'make bootstrap' or set ANDROID_SDK_ROOT." >&2
    return 1
  fi
}

require_exact_authorized_device() {
  local adb="$1"
  local requested_serial="${2:-}"
  local serial
  local -a serials=()
  while IFS= read -r serial; do
    [[ -n "$serial" ]] && serials+=("$serial")
  done < <("$adb" devices | awk 'NR > 1 && $2 == "device" { print $1 }')

  if [[ -n "$requested_serial" ]]; then
    if [[ ! " ${serials[*]} " == *" $requested_serial "* ]]; then
      echo "Requested serial '$requested_serial' is not an authorized ADB device. Check 'adb devices -l'." >&2
      return 1
    fi
    printf '%s\n' "$requested_serial"
    return 0
  fi

  if [[ "${#serials[@]}" -ne 1 ]]; then
    echo "Expected exactly one authorized ADB device; found ${#serials[@]}. Use --serial <serial> when more than one is connected." >&2
    "$adb" devices -l >&2
    return 1
  fi
  printf '%s\n' "${serials[0]}"
}
