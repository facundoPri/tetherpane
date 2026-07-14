#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/TetherPane.xcodeproj"
PROJECT_FILE="$PROJECT/project.pbxproj"
SCHEME="$PROJECT/xcshareddata/xcschemes/TetherPane.xcscheme"
ASSET_CATALOG="$ROOT_DIR/Configuration/macOS/Assets.xcassets"
APP_ICON="$ASSET_CATALOG/AppIcon.appiconset"
INFO_PLIST="$ROOT_DIR/Configuration/macOS/Info.plist"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$PROJECT_FILE" ]] || fail "missing Xcode project: $PROJECT_FILE"
[[ -f "$SCHEME" ]] || fail "missing shared app scheme: $SCHEME"
[[ -f "$ASSET_CATALOG/Contents.json" ]] || fail "missing asset catalog metadata"
[[ -f "$APP_ICON/Contents.json" ]] || fail "missing AppIcon metadata"

for icon in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png; do
  [[ -f "$APP_ICON/$icon" ]] || fail "missing AppIcon rendition: $icon"
done

[[ "$(plutil -extract CFBundleDisplayName raw "$INFO_PLIST")" == "TetherPane" ]] || fail "unexpected display name"
[[ "$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")" == "TetherPane" ]] || fail "unexpected executable name"
[[ "$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")" == "com.facundopri.tetherpane" ]] || fail "unexpected bundle identifier"

grep -Fq 'productName = TetherPane;' "$PROJECT_FILE" || fail "missing native TetherPane app target"
grep -Fq 'AirDroidDomain' "$PROJECT_FILE" || fail "missing local AirDroidDomain package dependency"
grep -Fq 'AirDroidScrcpy' "$PROJECT_FILE" || fail "missing local AirDroidScrcpy package dependency"
grep -Fq 'Configuration/macOS/Info.plist' "$PROJECT_FILE" || fail "Xcode target does not own canonical bundle metadata"
grep -Fq 'Configuration/macOS/Assets.xcassets' "$PROJECT_FILE" || fail "Xcode target does not own the app icon catalog"
grep -Fq 'Configuration/macOS/PrivacyInfo.xcprivacy' "$PROJECT_FILE" || fail "Xcode target does not own the privacy manifest"

plutil -lint "$INFO_PLIST" "$ROOT_DIR/Configuration/macOS/PrivacyInfo.xcprivacy" >/dev/null
xmllint --noout "$SCHEME"
ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)) }' \
  "$ASSET_CATALOG/Contents.json" \
  "$APP_ICON/Contents.json"

if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
  DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/tetherpane-derived-data.XXXXXX")"
  trap 'rm -rf "$DERIVED_DATA"' EXIT
  xcodebuild \
    -project "$PROJECT" \
    -scheme TetherPane \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build
else
  echo "SKIP: full Xcode is not selected; structural Xcode contract passed"
fi

echo "PASS: TetherPane has a shared, buildable Xcode-native macOS app contract"
