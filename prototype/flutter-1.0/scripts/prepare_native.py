#!/usr/bin/env python3
"""Reproducible resources: fixed SDK, verified APK, 4.6 overrides and unchanged MWM files.

No signing material is required or downloaded. Run before either platform build.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TAG = '2026.09.29-32-android'
APK_SHA = 'd7dbdfc3cbfdbcce6d437f11147f2cd15384c03052d2b4594fd8c1c7777dd497'
SOURCE_SHA = '799ad94afb6e0f72936cfb004faed914a89f5695c5c2719c79d517d6fa11c608'
CACHE = Path(os.environ.get('MUKSHAT_BUILD_CACHE', str(Path(tempfile.gettempdir()) / 'mukshat-build-cache')))
CACHE.mkdir(parents=True, exist_ok=True)

def checksum(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): value.update(block)
    return value.hexdigest()

def fetch(url, path, expected):
    if path.is_file() and checksum(path) == expected: return
    part = path.with_suffix(path.suffix + '.part')
    with urllib.request.urlopen(url, timeout=120) as response, part.open('wb') as stream:
        shutil.copyfileobj(response, stream)
    if checksum(part) != expected: raise RuntimeError('Integrity check failed: ' + path.name)
    part.replace(path)

apk = CACHE / 'organicmaps.apk'
fetch(f'https://github.com/organicmaps/organicmaps/releases/download/{TAG}/OrganicMaps-26092932-web-release.apk', apk, APK_SHA)
source = CACHE / 'organicmaps-source.tar.gz'
fetch(f'https://codeload.github.com/organicmaps/organicmaps/tar.gz/refs/tags/{TAG}', source, SOURCE_SHA)
vendor = ROOT / 'vendor/organicmaps'
with tarfile.open(source) as archive:
    for member in archive:
        relative = member.name.split('/', 1)[-1]
        if relative.startswith(('android/sdk/src/main/java/', 'android/sdk/src/main/res/', 'android/sdk/location/core/src/main/')) or relative in ['LICENSE', 'LICENSES/Apache-2.0.txt', 'NOTICE', 'DATA_LICENSE.txt']:
            # Upstream license may be a symlink. Its actual license text is selected above.
            if member.issym() or member.islnk(): continue
            member.name = relative
            archive.extract(member, vendor, filter='data')
assets = ROOT / 'android/organic-sdk/src/main/assets'
# APK baseline profiles belong to the original application, not this SDK consumer.
if (assets / 'dexopt').is_dir(): shutil.rmtree(assets / 'dexopt')
libs = ROOT / 'android/organic-sdk/src/main/jniLibs'
with zipfile.ZipFile(apk) as archive:
    for entry in archive.infolist():
        if entry.filename.startswith('assets/') and not entry.filename.startswith('assets/dexopt/') and not entry.is_dir():
            relative = Path(entry.filename).relative_to('assets')
            if '..' in relative.parts: raise RuntimeError('Invalid asset path')
            target = assets / relative; target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))
    for abi in ['arm64-v8a', 'x86', 'x86_64']:
        target = libs / abi / 'liborganicmaps.so'; target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(f'lib/{abi}/liborganicmaps.so'))
for entry in json.loads((ROOT / 'native-resources/manifest.json').read_text()):
    source_file = ROOT / 'native-resources/overrides' / entry['path']
    if checksum(source_file) != entry['sha256']: raise RuntimeError('Modified override: ' + entry['path'])
    target = assets / entry['path']; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source_file, target)
spec = importlib.util.spec_from_file_location('native_patch', ROOT / 'scripts/upstream/patch_country_scale.py')
patcher = importlib.util.module_from_spec(spec); spec.loader.exec_module(patcher)
patcher.patch(libs)
regions = [
    ('Saudi Arabia_North.mwm','1a7BwcYn1SsV1gPIvdvyfNN95E97hoV5R','6cd35fcb5b2bcd8c0ce5f9249426126c1a3c56635033c07fde855b9316651fe0'),
    ('Saudi Arabia_South.mwm','1oGhGU__h1XZzBMTZfJnnnv5r-ftJE6kk','7591a4c97628994b04856b84988ea6259bda4bf4c194702ef39817f02d484425'),
]
for name, drive_id, expected in regions:
    target = assets / 'regions' / name; target.parent.mkdir(parents=True, exist_ok=True)
    fetch(f'https://drive.usercontent.google.com/download?id={drive_id}&export=download', target, expected)
print('Verified SDK, Arabic fonts, sand style, Android engines and both MWM regions are ready.')
