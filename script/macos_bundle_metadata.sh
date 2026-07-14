#!/usr/bin/env bash

MACOS_INFO_PLIST_SOURCE="$ROOT_DIR/Configuration/macOS/Info.plist"
[[ -f "$MACOS_INFO_PLIST_SOURCE" ]] || {
  echo "Missing canonical bundle metadata: $MACOS_INFO_PLIST_SOURCE" >&2
  return 1 2>/dev/null || exit 1
}

MACOS_APP_EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$MACOS_INFO_PLIST_SOURCE")"
MACOS_BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$MACOS_INFO_PLIST_SOURCE")"
MACOS_MINIMUM_SYSTEM_VERSION="$(plutil -extract LSMinimumSystemVersion raw "$MACOS_INFO_PLIST_SOURCE")"
