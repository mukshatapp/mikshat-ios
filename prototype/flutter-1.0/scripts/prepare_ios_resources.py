"""Use exactly the Android prototype's reviewed map resources in the iOS build."""
from pathlib import Path
import plistlib
import shutil
root = Path(__file__).resolve().parents[1]
source = root / 'android/organic-sdk/src/main/assets'
target = root / 'ios/Native/Artifacts/MukshatData.bundle'
if not (source / 'World.mwm').is_file():
    raise SystemExit('Prepare verified native assets first, using scripts/prepare_native.py')
shutil.copytree(source, target, dirs_exist_ok=True)
with (target / 'Info.plist').open('wb') as stream:
    plistlib.dump({'CFBundleIdentifier': 'com.mikshat.prototype.data', 'CFBundleName': 'MukshatData',
                  'CFBundlePackageType': 'BNDL', 'CFBundleVersion': '1'}, stream)
print('iOS resources copied from the same MWM/font/style files as Android')
