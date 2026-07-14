#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE=""
EXPECTED_VERSION=""
EXPECTED_BUILD_NUMBER=""
EXPECTED_SIGNATURE=""
EXPECTED_ARCHITECTURE=""
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=macos_bundle_metadata.sh
source "$ROOT_DIR/script/macos_bundle_metadata.sh"

usage() {
  echo "usage: $0 --app <bundle> --version <version> --build-number <number> --signature <ad-hoc|developer-id> --architecture <native|universal|arm64|x86_64>" >&2
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --app)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      APP_BUNDLE="$2"
      shift 2
      ;;
    --version)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      EXPECTED_VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      EXPECTED_BUILD_NUMBER="$2"
      shift 2
      ;;
    --signature)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      EXPECTED_SIGNATURE="$2"
      shift 2
      ;;
    --architecture)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      EXPECTED_ARCHITECTURE="$2"
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

[[ -n "$APP_BUNDLE" && -n "$EXPECTED_VERSION" && -n "$EXPECTED_BUILD_NUMBER" && -n "$EXPECTED_ARCHITECTURE" ]] || {
  usage
  exit 2
}
[[ "$EXPECTED_SIGNATURE" == "ad-hoc" || "$EXPECTED_SIGNATURE" == "developer-id" ]] || {
  usage
  exit 2
}
[[ "$EXPECTED_ARCHITECTURE" == "native" || "$EXPECTED_ARCHITECTURE" == "universal" || "$EXPECTED_ARCHITECTURE" == "arm64" || "$EXPECTED_ARCHITECTURE" == "x86_64" ]] || {
  usage
  exit 2
}
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$MACOS_APP_EXECUTABLE"
PRIVACY_MANIFEST="$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
COMPILED_ASSETS="$APP_BUNDLE/Contents/Resources/Assets.car"

[[ -x "$APP_BINARY" ]] || { echo "Missing app executable: $APP_BINARY" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { echo "Missing Info.plist: $INFO_PLIST" >&2; exit 1; }
[[ -f "$PRIVACY_MANIFEST" ]] || { echo "Missing privacy manifest: $PRIVACY_MANIFEST" >&2; exit 1; }
[[ -f "$APP_ICON" || -f "$COMPILED_ASSETS" ]] || {
  echo "Missing compiled app icon resources." >&2
  exit 1
}

plutil -lint "$INFO_PLIST" "$PRIVACY_MANIFEST" >/dev/null

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plutil -extract "$key" raw "$INFO_PLIST")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected $key: expected '$expected', found '$actual'." >&2
    exit 1
  fi
}

assert_plist_value CFBundleExecutable "$MACOS_APP_EXECUTABLE"
assert_plist_value CFBundleIdentifier "$MACOS_BUNDLE_IDENTIFIER"
assert_plist_value CFBundlePackageType APPL
assert_plist_value CFBundleShortVersionString "$EXPECTED_VERSION"
assert_plist_value CFBundleVersion "$EXPECTED_BUILD_NUMBER"
assert_plist_value LSMinimumSystemVersion "$MACOS_MINIMUM_SYSTEM_VERSION"

local_network_description="$(plutil -extract NSLocalNetworkUsageDescription raw "$INFO_PLIST")"
[[ -n "$local_network_description" ]] || {
  echo "The app needs a user-facing local-network usage description." >&2
  exit 1
}

bonjour_services="$(plutil -extract NSBonjourServices xml1 -o - "$INFO_PLIST")"
for service in _adb._tcp _adb-tls-connect._tcp _adb-tls-pairing._tcp; do
  [[ "$bonjour_services" == *"<string>$service</string>"* ]] || {
    echo "Missing Bonjour service declaration: $service" >&2
    exit 1
  }
done

tracking="$(plutil -extract NSPrivacyTracking raw "$PRIVACY_MANIFEST")"
[[ "$tracking" == "false" ]] || {
  echo "Privacy manifest must declare that the app does not track users." >&2
  exit 1
}

privacy_access="$(plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$PRIVACY_MANIFEST")"
[[ "$privacy_access" == *"NSPrivacyAccessedAPICategoryUserDefaults"* && "$privacy_access" == *"CA92.1"* ]] || {
  echo "Privacy manifest must describe app-private UserDefaults access." >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
signing_details="$(codesign -dvvv "$APP_BUNDLE" 2>&1)"
[[ "$signing_details" == *"Info.plist entries="* && "$signing_details" != *"Info.plist=not bound"* ]] || {
  echo "The code signature does not seal Info.plist." >&2
  exit 1
}
[[ "$signing_details" == *"runtime"* ]] || {
  echo "The app is not signed with the hardened runtime." >&2
  exit 1
}

entitlements="$(codesign -d --entitlements :- "$APP_BUNDLE" 2>&1 || true)"
if [[ "$entitlements" == *"com.apple.security.get-task-allow"* ]]; then
  echo "Release bundle contains the debug-only get-task-allow entitlement." >&2
  exit 1
fi

case "$EXPECTED_SIGNATURE" in
  ad-hoc)
    [[ "$signing_details" == *"Signature=adhoc"* ]] || {
      echo "Expected an ad-hoc local signature." >&2
      exit 1
    }
    ;;
  developer-id)
    [[ "$signing_details" == *"Authority=Developer ID Application:"* ]] || {
      echo "Expected a Developer ID Application signature." >&2
      exit 1
    }
    [[ "$signing_details" == *"Timestamp="* ]] || {
      echo "Developer ID signature is missing its secure timestamp." >&2
      exit 1
    }
    ;;
esac

architectures="$(lipo -archs "$APP_BINARY")"
[[ -n "$architectures" ]] || {
  echo "Could not determine the app executable architecture." >&2
  exit 1
}

assert_architecture() {
  local architecture="$1"
  [[ " $architectures " == *" $architecture "* ]] || {
    echo "Expected architecture '$architecture', found '$architectures'." >&2
    exit 1
  }
}

case "$EXPECTED_ARCHITECTURE" in
  native)
    assert_architecture "$(uname -m)"
    ;;
  universal)
    assert_architecture arm64
    assert_architecture x86_64
    ;;
  arm64|x86_64)
    assert_architecture "$EXPECTED_ARCHITECTURE"
    ;;
esac

printf 'Verified bundle: %s (%s)\n' "$APP_BUNDLE" "$architectures"
