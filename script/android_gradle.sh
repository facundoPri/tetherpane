#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

export_android_environment
cd "$ROOT_DIR/apps/android"

if [[ ! -x ./gradlew ]]; then
  echo "Android Gradle wrapper is missing. Restore apps/android/gradlew from the repository." >&2
  exit 1
fi

exec ./gradlew "$@"
