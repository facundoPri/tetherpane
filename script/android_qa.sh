#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

PACKAGE_NAME="com.facundopri.tetherpane.companion"
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

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to derive the onboarding button coordinates from the UI tree." >&2
  exit 1
}

adb="$(resolve_adb)" || {
  echo "ADB is unavailable. Install platform-tools or set ADB_PATH." >&2
  exit 1
}
serial="$(require_exact_authorized_device "$adb" "$SERIAL")"
artifacts_dir="$(mktemp -d "${TMPDIR:-/tmp}/tetherpane-android-qa.XXXXXX")"

printf 'QA artifacts: %s\n' "$artifacts_dir"
printf 'Target serial: %s\n' "$serial"

capture_ui_tree() {
  local destination="$1"
  "$adb" -s "$serial" exec-out uiautomator dump /dev/tty |
    python3 -c 'import sys
content = sys.stdin.read()
marker = "</hierarchy>"
end = content.find(marker)
if end == -1:
    raise SystemExit("uiautomator did not produce a UI hierarchy")
sys.stdout.write(content[:end + len(marker)])' > "$destination"
}

"$adb" -s "$serial" logcat -c
"$SCRIPT_DIR/android_install.sh" --serial "$serial"

sleep 2
ui_tree="$artifacts_dir/onboarding-ui.xml"
capture_ui_tree "$ui_tree"
"$adb" -s "$serial" exec-out screencap -p > "$artifacts_dir/onboarding.png"

python3 - "$ui_tree" "$artifacts_dir/onboarding-ui-summary.txt" <<'PY'
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
lines = []
for node in tree.iter("node"):
    text = node.attrib.get("text") or node.attrib.get("content-desc")
    if text:
        lines.append(f"{text} {node.attrib.get('bounds', '')}")
with open(sys.argv[2], "w", encoding="utf-8") as output:
    output.write("\n".join(lines) + "\n")
PY

tap_point="$(python3 - "$ui_tree" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

target = "Open Developer options"
for node in ET.parse(sys.argv[1]).iter("node"):
    if node.attrib.get("text") == target or node.attrib.get("content-desc") == target:
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
        if match:
            left, top, right, bottom = map(int, match.groups())
            print((left + right) // 2, (top + bottom) // 2)
            raise SystemExit(0)
raise SystemExit("The onboarding action was not present in the UI tree.")
PY
)"

read -r tap_x tap_y <<EOF
$tap_point
EOF
"$adb" -s "$serial" shell input tap "$tap_x" "$tap_y"
settings_tree="$artifacts_dir/after-settings-ui.xml"
settings_reached=false
for _ in $(seq 1 5); do
  sleep 1
  capture_ui_tree "$settings_tree"
  if python3 - "$settings_tree" <<'PY'
import sys
import xml.etree.ElementTree as ET

for node in ET.parse(sys.argv[1]).iter("node"):
    if node.attrib.get("package") == "com.android.settings":
        raise SystemExit(0)
raise SystemExit(1)
PY
  then
    settings_reached=true
    break
  fi
done
"$adb" -s "$serial" exec-out screencap -p > "$artifacts_dir/after-settings.png"

pid="$("$adb" -s "$serial" shell pidof -s "$PACKAGE_NAME" 2>/dev/null | tr -d '\r' || true)"
if [[ -n "$pid" ]]; then
  "$adb" -s "$serial" logcat -d -v threadtime --pid "$pid" > "$artifacts_dir/logcat.txt"
else
  "$adb" -s "$serial" logcat -d -v threadtime -t 300 > "$artifacts_dir/logcat.txt"
fi

component="$("$adb" -s "$serial" shell cmd package resolve-activity --brief "$PACKAGE_NAME" | tr -d '\r' | tail -n 1)"
if [[ "$component" == */* ]]; then
  "$adb" -s "$serial" shell am start -n "$component" >/dev/null
fi

if [[ "$settings_reached" != true ]]; then
  echo "The onboarding action did not bring Android Settings to the foreground. Developer options may be disabled; enable it first, then rerun QA. Artifacts: $artifacts_dir" >&2
  exit 1
fi

printf 'QA complete. Inspect %s\n' "$artifacts_dir"
