#!/usr/bin/env bash
set -euo pipefail
prototype_root=$(cd "$(dirname "$0")/.." && pwd)
native_root="$prototype_root/ios/Native"
engine_root="$native_root/Engine"
sdk_name=${1:-iphonesimulator}
phase=${2:-all}
engine_tag=2026.09.29-32-android
case "$sdk_name" in iphoneos|iphonesimulator) ;; *) exit 2 ;; esac
case "$phase" in all|core-only|rendering-only) ;; *) exit 2 ;; esac
if [[ ! -d "$engine_root/.git" ]]; then
  git clone --branch "$engine_tag" --depth 1 --recurse-submodules --shallow-submodules https://github.com/organicmaps/organicmaps.git "$engine_root"
fi
actual_tag=$(git -C "$engine_root" describe --tags --exact-match)
[[ "$actual_tag" == "$engine_tag" ]] || { echo 'Unexpected engine revision'; exit 1; }
[[ -f "$engine_root/private.h" ]] || { echo 'Pinned engine configuration is missing'; exit 1; }
if ! git -C "$engine_root" apply --reverse --check "$prototype_root/scripts/upstream/country-scale.patch" 2>/dev/null; then
  git -C "$engine_root" apply "$prototype_root/scripts/upstream/country-scale.patch"
fi
mkdir -p "$native_root/Artifacts"
native_build="$native_root/Build-$sdk_name"
core_signature=$(python3 - "$engine_root" "$sdk_name" "$prototype_root/scripts/upstream/country-scale.patch" "$0" <<'PY'
import hashlib,pathlib,subprocess,sys
digest=hashlib.sha256()
digest.update(subprocess.check_output(['git','-C',sys.argv[1],'rev-parse','HEAD']))
digest.update(sys.argv[2].encode())
digest.update(pathlib.Path(sys.argv[3]).read_bytes())
digest.update(pathlib.Path(sys.argv[4]).read_bytes())
digest.update(subprocess.check_output(['xcodebuild','-version']))
print(digest.hexdigest())
PY
)
if [[ "$phase" != rendering-only ]]; then
  cached_signature=""
  if [[ -f "$native_root/Artifacts/core-build-key.txt" ]]; then
    cached_signature=$(cat "$native_root/Artifacts/core-build-key.txt")
  fi
  if [[ ! -f "$native_root/Artifacts/libMukshatCore.a" || "$cached_signature" != "$core_signature" ]]; then
    cmake -S "$engine_root" -B "$native_build" -G Xcode \
      -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_name" \
      -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
      -DSKIP_QT_GUI=ON -DBUILD_TESTING=OFF -DCMAKE_UNITY_BUILD=OFF \
      -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    cmake --build "$native_build" --config Release --target map --parallel 3
    python3 - "$native_build" "$native_root/Artifacts/libMukshatCore.a" <<'PY'
import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]);libraries=sorted(str(p) for p in root.rglob('*.a') if 'Release' in str(p))
if not libraries: raise SystemExit('No engine archives were built')
subprocess.run(['xcrun','libtool','-static','-o',sys.argv[2],*libraries],check=True)
PY
    printf '%s' "$core_signature" > "$native_root/Artifacts/core-build-key.txt"
  fi
fi
if [[ "$phase" != core-only ]]; then
  metal_build="$native_build/metal"
  mkdir -p "$metal_build"
  # shaders_lib.metal provides functions referenced by the other Metal units.
  for shader in "$engine_root"/libs/shaders/Metal/*.metal; do
    xcrun -sdk "$sdk_name" metal -std=ios-metal2.3 -I "$engine_root/libs/shaders/Metal" \
      -c "$shader" -o "$metal_build/$(basename "$shader" .metal).air"
  done
  xcrun -sdk "$sdk_name" metallib "$metal_build"/*.air -o "$native_root/Artifacts/default.metallib"
  python3 "$prototype_root/scripts/prepare_ios_resources.py"
fi
