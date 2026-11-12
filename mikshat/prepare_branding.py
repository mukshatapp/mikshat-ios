"""Package the approved square artwork at Apple's required app-icon dimensions."""
from pathlib import Path
import json
import subprocess
root = Path(__file__).resolve().parents[1]
artwork = root / 'mikshat/branding/app-icon.png'
assets = root / 'iphone/Maps/Resources/Images.xcassets'
for name in ('AppIcon', 'AppIconDebug'):
    folder = assets / f'{name}.appiconset'
    subprocess.run(['sips', '-z', '1024', '1024', str(artwork), '--out', str(folder / '1024.png')], check=True)
    (folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': '1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
        'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
