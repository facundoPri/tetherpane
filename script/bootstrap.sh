#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install JDK 17 and Android command-line tools." >&2
  exit 1
fi

if ! brew list --versions openjdk@17 >/dev/null 2>&1; then
  echo "Installing openjdk@17 with Homebrew…"
  brew install openjdk@17
fi

if ! brew list --cask --versions android-commandlinetools >/dev/null 2>&1; then
  echo "Installing android-commandlinetools with Homebrew…"
  brew install --cask android-commandlinetools
fi

java_home="$(resolve_java_home)"
sdkmanager="$(resolve_sdkmanager)"
sdk_root="$(resolve_android_sdk_root)"
export JAVA_HOME="$java_home"
export ANDROID_SDK_ROOT="$sdk_root"
export ANDROID_HOME="$sdk_root"
mkdir -p "$sdk_root"

if [[ ! -t 0 ]]; then
  cat >&2 <<EOF
Android SDK licenses require explicit interactive acceptance and have not been accepted.
Run this command from your terminal:
  make bootstrap
It will show each Android SDK license before installing platform-tools, API 36,
and Build Tools 36.0.0. No shell profile will be changed.
EOF
  exit 2
fi

echo "Android SDK licenses will now be shown for your review."
"$sdkmanager" --sdk_root="$sdk_root" --licenses
"$sdkmanager" --sdk_root="$sdk_root" \
  "platform-tools" \
  "cmdline-tools;latest" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "emulator" \
  "system-images;android-36;google_apis;arm64-v8a"

echo "Bootstrap complete. Android SDK root: $sdk_root"
