#!/usr/bin/env bash
# SOURCE_ROOT OUTPUT_DIRECTORY BOOTED_UDID LABEL VARIANT EXPECTED_RESULT
set -euo pipefail
source_root=$1
output_directory=$2
simulator_udid=$3
probe_label=$4
probe_variant=$5
expected_result=$6
probe_scripts=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd)
python3 "$probe_scripts/prepare_probe.py" --source-root "$source_root" --output "$output_directory/generated" --label "$probe_label" --variant "$probe_variant"
probe_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
probe_target="$(uname -m)-apple-ios15.0-simulator"
probe_app="$output_directory/TabLayoutProbe.app"
mkdir -p "$probe_app"
xcrun --sdk iphonesimulator swiftc -sdk "$probe_sdk" -target "$probe_target" -swift-version 5 -parse-as-library -O -whole-module-optimization \
  "$output_directory/generated/Probe.swift" -framework UIKit -o "$probe_app/TabLayoutProbe" 2>&1 | tee "$output_directory/swiftc.log"
probe_bundle="com.mikshat.tablayoutprobe.$probe_label"
python3 - "$probe_app/Info.plist" "$probe_bundle" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump(dict(CFBundleIdentifier=sys.argv[2], CFBundleExecutable='TabLayoutProbe',
                      CFBundleName='TabLayoutProbe', CFBundleDisplayName='TabLayoutProbe',
                      CFBundleVersion='1', CFBundleShortVersionString='1.0',
                      CFBundlePackageType='APPL', MinimumOSVersion='15.0',
                      CFBundleSupportedPlatforms=['iPhoneSimulator'], LSRequiresIPhoneOS=True,
                      UIDeviceFamily=[1], UILaunchScreen={},
                      UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait']), stream)
PY
codesign --force --sign - "$probe_app"
xcrun simctl uninstall "$simulator_udid" "$probe_bundle" >/dev/null 2>&1 || true
xcrun simctl install "$simulator_udid" "$probe_app"
python3 - "$simulator_udid" "$probe_bundle" "$output_directory" "$expected_result" <<'PY'
from pathlib import Path
import json, subprocess, sys
udid, bundle, directory, expected = sys.argv[1:]
output = Path(directory)
try:
    result = subprocess.run(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process', udid, bundle],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    log = result.stdout
except subprocess.TimeoutExpired as error:
    (output / 'launch.log').write_bytes(error.stdout or b'')
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], check=False)
    (output / 'probe-outcome.json').write_text(json.dumps({'result': 'timeout', 'expected': expected}) + '\n')
    raise SystemExit('Tab layout probe timed out')
(output / 'launch.log').write_bytes(log)
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, bundle, 'data'], text=True).strip()
report = Path(container) / 'Documents/probe-result.json'
payload = json.loads(report.read_text()) if report.exists() else {'result': 'terminated_without_report', 'returnCode': result.returncode}
payload.update(expected=expected, optimization='-O -whole-module-optimization')
(output / 'probe-outcome.json').write_text(json.dumps(payload, indent=2) + '\n')
print(json.dumps(payload))
if payload['result'] != expected:
    print(log[-15000:].decode(errors='replace'))
    raise SystemExit(f"Expected {expected}, got {payload['result']}")
PY
