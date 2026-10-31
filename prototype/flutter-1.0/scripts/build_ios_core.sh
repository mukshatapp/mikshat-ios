#!/usr/bin/env bash
set -euo pipefail
prototype_root=$(cd "$(dirname "$0")/.." && pwd)
native_root="$prototype_root/ios/Native"
engine_root="$native_root/Engine"
sdk_name=${1:-iphonesimulator}
engine_tag=2026.09.29-32-android
if [[ ! -d "$engine_root/.git" ]]; then
  git clone --branch "$engine_tag" --depth 1 --recurse-submodules --shallow-submodules https://github.com/organicmaps/organicmaps.git "$engine_root"
fi
actual_tag=$(git -C "$engine_root" describe --tags --exact-match)
[[ "$actual_tag" == "$engine_tag" ]] || { echo 'Unexpected engine revision'; exit 1; }
[[ -f "$engine_root/private.h" ]] || { echo "Pinned engine configuration is missing"; exit 1; }
if ! git -C "$engine_root" apply --reverse --check "$prototype_root/scripts/upstream/country-scale.patch" 2>/dev/null; then
  git -C "$engine_root" apply "$prototype_root/scripts/upstream/country-scale.patch"
fi
native_build="$native_root/Build-$sdk_name"
cmake -S "$engine_root" -B "$native_build" -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_name" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DSKIP_QT_GUI=ON -DBUILD_TESTING=OFF -DCMAKE_UNITY_BUILD=OFF \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
cmake --build "$native_build" --config Release --target map --parallel 3
mkdir -p "$native_root/Artifacts"
python3 - "$native_build" "$native_root/Artifacts/libMukshatCore.a" <<'PY'
import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);libraries=sorted(str(p) for p in root.rglob('*.a') if 'Release' in str(p))
if not libraries: raise SystemExit('No engine archives were built')
subprocess.run(['xcrun','libtool','-static','-o',sys.argv[2],*libraries],check=True)
PY
# The native Metal context loads the default library from the application bundle.
metal_build="$native_build/metal"
mkdir -p "$metal_build"
for shader in "$engine_root"/libs/shaders/Metal/*.metal; do
  [[ $(basename "$shader") == shaders_lib.metal ]] && continue
  xcrun -sdk "$sdk_name" metal -std=ios-metal2.3 -I "$engine_root/libs/shaders/Metal" \
    -c "$shader" -o "$metal_build/$(basename "$shader" .metal).air"
done
xcrun -sdk "$sdk_name" metallib "$metal_build"/*.air -o "$native_root/Artifacts/default.metallib"
python3 "$prototype_root/scripts/prepare_ios_resources.py"
