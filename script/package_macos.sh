#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=macos_bundle_metadata.sh
source "$ROOT_DIR/script/macos_bundle_metadata.sh"
APP_NAME="$MACOS_APP_EXECUTABLE"
CONFIGURATION="release"
VERSION="0.1.0"
BUILD_NUMBER="1"
ARCHITECTURE="native"
BUILD_SYSTEM="auto"
SIGNING_IDENTITY="-"
OUTPUT_DIR="$ROOT_DIR/dist/release"
CREATE_ARCHIVE=true
NOTARY_PROFILE=""
INFO_PLIST_SOURCE="$MACOS_INFO_PLIST_SOURCE"
PRIVACY_MANIFEST_SOURCE="$ROOT_DIR/Configuration/macOS/PrivacyInfo.xcprivacy"
APP_ICON_SOURCE="$ROOT_DIR/Configuration/macOS/AppIcon.icns"
XCODE_PROJECT="$ROOT_DIR/TetherPane.xcodeproj"

usage() {
  cat >&2 <<'USAGE'
usage: package_macos.sh [options]

Options:
  --configuration <debug|release>   Build configuration (default: release)
  --build-system <auto|xcode|swiftpm> Prefer Xcode when available, or force one path
  --version <major.minor.patch>     User-visible release version (default: 0.1.0)
  --build-number <integer[.integer]> Machine-readable build version (default: 1)
  --architecture <native|universal|arm64|x86_64>
  --sign <identity|->               Code-signing identity; '-' creates an ad-hoc local build
  --output-dir <path>               Bundle and archive destination
  --skip-archive                    Produce only the .app bundle
  --notarize-profile <name>         notarytool keychain profile; requires Developer ID signing
USAGE
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --configuration)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      CONFIGURATION="$2"
      shift 2
      ;;
    --build-system)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      BUILD_SYSTEM="$2"
      shift 2
      ;;
    --version)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --architecture)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      ARCHITECTURE="$2"
      shift 2
      ;;
    --sign)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --output-dir)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-archive)
      CREATE_ARCHIVE=false
      shift
      ;;
    --notarize-profile)
      [[ "$#" -ge 2 ]] || { usage; exit 2; }
      NOTARY_PROFILE="$2"
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

[[ "$CONFIGURATION" == "debug" || "$CONFIGURATION" == "release" ]] || {
  echo "Configuration must be 'debug' or 'release'." >&2
  exit 2
}
[[ "$BUILD_SYSTEM" == "auto" || "$BUILD_SYSTEM" == "xcode" || "$BUILD_SYSTEM" == "swiftpm" ]] || {
  echo "Build system must be auto, xcode, or swiftpm." >&2
  exit 2
}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version must contain three numeric components, for example 1.2.3." >&2
  exit 2
}
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
  echo "Build number must contain one to three numeric components." >&2
  exit 2
}
[[ -f "$INFO_PLIST_SOURCE" && -f "$PRIVACY_MANIFEST_SOURCE" && -f "$APP_ICON_SOURCE" ]] || {
  echo "macOS bundle metadata is missing from Configuration/macOS." >&2
  exit 1
}

if [[ -n "$NOTARY_PROFILE" && "$SIGNING_IDENTITY" == "-" ]]; then
  echo "Notarization requires a Developer ID Application signing identity." >&2
  exit 2
fi
if [[ -n "$NOTARY_PROFILE" && "$CREATE_ARCHIVE" != true ]]; then
  echo "Notarization requires the release archive; remove --skip-archive." >&2
  exit 2
fi
if [[ "$SIGNING_IDENTITY" != "-" && "$CONFIGURATION" != "release" ]]; then
  echo "Developer ID distribution requires a release configuration." >&2
  exit 2
fi

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ARCHIVE="$OUTPUT_DIR/$APP_NAME-$VERSION-macos.zip"
XCODE_AVAILABLE=false
if [[ -f "$XCODE_PROJECT/project.pbxproj" ]] && command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  XCODE_AVAILABLE=true
fi

if [[ "$BUILD_SYSTEM" == "auto" ]]; then
  if [[ "$XCODE_AVAILABLE" == true ]]; then
    BUILD_SYSTEM="xcode"
  else
    BUILD_SYSTEM="swiftpm"
  fi
fi
if [[ "$BUILD_SYSTEM" == "xcode" && "$XCODE_AVAILABLE" != true ]]; then
  echo "The Xcode build path requires a full Xcode installation selected with xcode-select." >&2
  exit 1
fi
if [[ "$ARCHITECTURE" == "universal" && "$XCODE_AVAILABLE" != true ]]; then
  echo "A universal build requires a full Xcode installation selected with xcode-select." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE"

cd "$ROOT_DIR"
case "$BUILD_SYSTEM" in
  xcode)
    XCODE_CONFIGURATION="Release"
    [[ "$CONFIGURATION" == "debug" ]] && XCODE_CONFIGURATION="Debug"
    DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/tetherpane-derived-data.XXXXXX")"
    cleanup_derived_data() {
      rm -rf "$DERIVED_DATA"
    }
    trap cleanup_derived_data EXIT
    xcode_arguments=(
      -project "$XCODE_PROJECT"
      -scheme "$APP_NAME"
      -configuration "$XCODE_CONFIGURATION"
      -derivedDataPath "$DERIVED_DATA"
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
    )
    case "$ARCHITECTURE" in
      native)
        xcode_arguments+=("ARCHS=$(uname -m)" ONLY_ACTIVE_ARCH=YES)
        ;;
      arm64|x86_64)
        xcode_arguments+=("ARCHS=$ARCHITECTURE" ONLY_ACTIVE_ARCH=NO)
        ;;
      universal)
        xcode_arguments+=("ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
        ;;
      *)
        echo "Architecture must be native, universal, arm64, or x86_64." >&2
        exit 2
        ;;
    esac
    xcodebuild "${xcode_arguments[@]}" build
    BUILT_APP="$DERIVED_DATA/Build/Products/$XCODE_CONFIGURATION/$APP_NAME.app"
    [[ -d "$BUILT_APP" ]] || {
      echo "Xcode did not produce $BUILT_APP." >&2
      exit 1
    }
    /usr/bin/ditto "$BUILT_APP" "$APP_BUNDLE"
    ;;
  swiftpm)
    build_arguments=(-c "$CONFIGURATION" --product "$APP_NAME")
    case "$ARCHITECTURE" in
      native)
        ;;
      arm64|x86_64)
        build_arguments+=(--arch "$ARCHITECTURE")
        ;;
      universal)
        build_arguments+=(--arch arm64 --arch x86_64)
        ;;
      *)
        echo "Architecture must be native, universal, arm64, or x86_64." >&2
        exit 2
        ;;
    esac
    swift build "${build_arguments[@]}"
    BUILD_DIRECTORY="$(swift build "${build_arguments[@]}" --show-bin-path)"
    BUILD_BINARY="$BUILD_DIRECTORY/$APP_NAME"
    [[ -x "$BUILD_BINARY" ]] || {
      echo "SwiftPM did not produce $BUILD_BINARY." >&2
      exit 1
    }
    mkdir -p "$APP_MACOS" "$APP_RESOURCES"
    cp "$BUILD_BINARY" "$APP_BINARY"
    chmod +x "$APP_BINARY"
    cp "$INFO_PLIST_SOURCE" "$INFO_PLIST"
    cp "$PRIVACY_MANIFEST_SOURCE" "$APP_RESOURCES/PrivacyInfo.xcprivacy"
    cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
    plutil -replace CFBundleIconFile -string "AppIcon.icns" "$INFO_PLIST"
    ;;
esac

plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"
plutil -lint "$INFO_PLIST" "$APP_RESOURCES/PrivacyInfo.xcprivacy" >/dev/null

xattr -cr "$APP_BUNDLE"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --options runtime --timestamp=none --sign - "$APP_BUNDLE"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi

"$ROOT_DIR/script/verify_macos_bundle.sh" \
  --app "$APP_BUNDLE" \
  --version "$VERSION" \
  --build-number "$BUILD_NUMBER" \
  --signature "$([[ "$SIGNING_IDENTITY" == "-" ]] && echo ad-hoc || echo developer-id)" \
  --architecture "$ARCHITECTURE"

create_archive() {
  rm -f "$ARCHIVE"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"
}

if [[ "$CREATE_ARCHIVE" == true ]]; then
  create_archive
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  create_archive
  spctl -a -vv --type execute "$APP_BUNDLE"
fi

printf 'App bundle: %s\n' "$APP_BUNDLE"
if [[ "$CREATE_ARCHIVE" == true ]]; then
  printf 'Release archive: %s\n' "$ARCHIVE"
fi
