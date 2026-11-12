#!/usr/bin/env bash
# Usage: run_probe.sh SOURCE_ROOT OUTPUT_DIRECTORY BOOTED_SIMULATOR_UDID LABEL
set -euo pipefail
source_root=$1
output_directory=$2
simulator_udid=$3
probe_label=$4
probe_scripts=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$output_directory"
output_directory=$(cd "$output_directory" && pwd)
python3 "$probe_scripts/prepare_probe.py" --source-root "$source_root" --output "$output_directory/generated" --label "$probe_label"
probe_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
probe_arch=$(uname -m)
probe_target="$probe_arch-apple-ios15.0-simulator"
probe_optimization=${MIKSHAT_PROBE_OPTIMIZATION:-debug}
case "$probe_optimization" in
  debug)
    swift_optimization=(-Onone)
    clang_optimization=(-O0)
    ;;
  release)
    swift_optimization=(-O -whole-module-optimization)
    clang_optimization=(-O2)
    ;;
  *)
    echo "MIKSHAT_PROBE_OPTIMIZATION must be debug or release" >&2
    exit 1
    ;;
esac
python3 - "$output_directory/generated/source-manifest.json" "$probe_optimization" "$probe_target" "$probe_sdk" <<'PY'
from pathlib import Path
import json, sys
path = Path(sys.argv[1])
value = json.loads(path.read_text())
value.update(optimization=sys.argv[2], target=sys.argv[3], sdk=sys.argv[4],
             swiftFlags=['-O', '-whole-module-optimization'] if sys.argv[2] == 'release' else ['-Onone'],
             clangFlags=['-O2'] if sys.argv[2] == 'release' else ['-O0'])
path.write_text(json.dumps(value, indent=2) + '\n')
print(json.dumps(value))
PY
probe_app="$output_directory/ThemeProbe.app"
mkdir -p "$probe_app"
xcrun --sdk iphonesimulator clang -target "$probe_target" -isysroot "$probe_sdk" -fobjc-arc -fmodules "${clang_optimization[@]}" \
  -I "$output_directory/generated" -c "$output_directory/generated/SwizzleStyle.m" -o "$output_directory/SwizzleStyle.o" \
  2>&1 | tee "$output_directory/clang.log"
xcrun --sdk iphonesimulator swiftc -sdk "$probe_sdk" -target "$probe_target" -swift-version 5 -parse-as-library "${swift_optimization[@]}" \
  -import-objc-header "$output_directory/generated/Bridge.h" "$output_directory/generated/Probe.swift" \
  "$output_directory/SwizzleStyle.o" -framework UIKit -o "$probe_app/ThemeProbe" \
  2>&1 | tee "$output_directory/swiftc.log"
probe_bundle="com.mikshat.themeprobe.$probe_label"
python3 - "$probe_app/Info.plist" "$probe_bundle" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as stream:
    plistlib.dump(dict(CFBundleIdentifier=sys.argv[2], CFBundleExecutable='ThemeProbe',
                      CFBundleName='ThemeProbe', CFBundleDisplayName='ThemeProbe',
                      CFBundleVersion='1', CFBundleShortVersionString='1.0',
                      CFBundlePackageType='APPL', MinimumOSVersion='15.0',
                      CFBundleSupportedPlatforms=['iPhoneSimulator'], LSRequiresIPhoneOS=True,
                      UIDeviceFamily=[1], UILaunchScreen={},
                      UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait']), stream)
PY
codesign --force --sign - "$probe_app"
# A previous successful run must not leave a stale result in the app container.
xcrun simctl uninstall "$simulator_udid" "$probe_bundle" >/dev/null 2>&1 || true
xcrun simctl install "$simulator_udid" "$probe_app"
python3 - "$simulator_udid" "$probe_bundle" "$output_directory" <<'PY'
from pathlib import Path
import json, subprocess, sys
udid, bundle, directory = sys.argv[1:]
output = Path(directory)
build_settings = json.loads((output / 'generated/source-manifest.json').read_text())
command = ['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process', udid, bundle]
try:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    log = result.stdout
except subprocess.TimeoutExpired as error:
    log = error.stdout or b''
    (output / 'launch.log').write_bytes(log)
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], check=False)
    (output / 'probe-outcome.json').write_text(json.dumps({'result': 'timeout', 'timeoutSeconds': 120,
                                                        'optimization': build_settings['optimization'],
                                                        'swiftFlags': build_settings['swiftFlags']}) + '\n')
    raise SystemExit('UIKit probe timed out; see launch.log and simulator crash reports')
(output / 'launch.log').write_bytes(log)
container = subprocess.run(['xcrun', 'simctl', 'get_app_container', udid, bundle, 'data'], capture_output=True, text=True, check=True).stdout.strip()
report = Path(container) / 'Documents/probe-result.json'
if report.exists():
    payload = json.loads(report.read_text())
else:
    payload = {'result': 'terminated_without_report', 'launchReturnCode': result.returncode}
payload.update(optimization=build_settings['optimization'], swiftFlags=build_settings['swiftFlags'],
               clangFlags=build_settings['clangFlags'])
(output / 'probe-outcome.json').write_text(json.dumps(payload, indent=2) + '\n')
print(json.dumps(payload))
if payload.get('result') != 'passed':
    print(log[-10000:].decode(errors='replace'))
    raise SystemExit(1)
PY
