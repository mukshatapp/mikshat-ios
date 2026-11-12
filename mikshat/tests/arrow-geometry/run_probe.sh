#!/usr/bin/env bash
# A real foreground UIKit scene, not an XCTest host or a source-level simulation.
set -euo pipefail
if [[ $# != 4 ]]; then
  echo "Usage: $0 SOURCE_ROOT OUTPUT_DIR BOOTED_IPHONE_UDID baseline|fixed" >&2
  exit 2
fi
source_root="$1"
output="$2"
device="$3"
variant="$4"
case "$variant" in baseline|fixed) ;; *) exit 2 ;; esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
rm -f "$output/probe-outcome.json" "$output/geometry-trace.jsonl"
generated="$output/generated"
app="$output/ArrowGeometryProbe.app"
bundle="com.mikshat.arrowgeometry.$variant"
python3 "$script_dir/prepare_probe.py" "$source_root" "$generated" --variant "$variant" > "$output/preparation.log"
mkdir -p "$app"
cp "$generated/Info.plist" "$app/Info.plist"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun swiftc --version > "$output/toolchain.log"
{
  xcrun swiftc -parse-as-library -swift-version 5 -O -whole-module-optimization \
    -module-name ArrowGeometryProbe -sdk "$sdk" -target arm64-apple-ios27.0-simulator \
    "$generated/ProductionIndicator.swift" "$generated/MikshatNavigationMath.swift" \
    "$generated/ProbeVariant.swift" "$generated/ProbeApp.swift" \
    -framework UIKit -framework CoreLocation -o "$app/ArrowGeometryProbe"
  codesign --force --sign - "$app"
} > "$output/compile.log" 2>&1 || { cat "$output/compile.log"; exit 3; }
# Only this disposable probe bundle is uninstalled. Never touch the real app.
xcrun simctl uninstall "$device" "$bundle" > "$output/uninstall.log" 2>&1 || true
xcrun simctl install "$device" "$app" > "$output/install.log" 2>&1
container="$(xcrun simctl get_app_container "$device" "$bundle" data)"
xcrun simctl launch --terminate-running-process "$device" "$bundle" > "$output/launch.log" 2>&1
cat "$output/launch.log"
for attempt in $(seq 1 50); do
  if [[ -f "$container/Documents/probe-outcome.json" ]]; then
    cp "$container/Documents/probe-outcome.json" "$output/probe-outcome.json"
    break
  fi
  sleep 1
done
if [[ -f "$container/Documents/geometry-trace.jsonl" ]]; then
  cp "$container/Documents/geometry-trace.jsonl" "$output/geometry-trace.jsonl"
fi
xcrun simctl io "$device" screenshot "$output/final-screen.png" > "$output/screenshot.log" 2>&1 || true
xcrun simctl terminate "$device" "$bundle" > "$output/terminate.log" 2>&1 || true
if [[ ! -f "$output/probe-outcome.json" ]]; then
  python3 - "$output/probe-outcome.json" "$variant" <<'PY'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text(json.dumps({"schema":1,"variant":sys.argv[2],"outcome":"setup-failed","reason":"no-durable-app-result-within-host-deadline","cases_completed":0}, indent=2))
PY
fi
python3 "$script_dir/verify_outcome.py" "$output"
