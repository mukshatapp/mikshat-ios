from pathlib import Path
import base64
import json
import shutil
import subprocess
import sys

udid = sys.argv[1]
target = Path(sys.argv[2])
target.mkdir(parents=True, exist_ok=True)
container = subprocess.check_output(["xcrun", "simctl", "get_app_container", udid,
                                      "com.mikshat.maps.debug", "data"], text=True).strip()
images = sorted((Path(container) / "Documents").glob("weather-*-fixture.png"))
for source in images:
    shutil.copy2(source, target / source.name)
print(json.dumps({"nativeWeatherImages": len(images), "names": [p.name for p in images],
                  "data": "synthetic injected forecasts", "renderer": "actual UIKit views"}))
for name in ["weather-light-portrait-fixture.png", "weather-dark-landscape-forecast-fixture.png"]:
    path = target / name
    if path.exists():
        preview = target / ("preview-" + name)
        subprocess.run(["sips", "-Z", "700", str(path), "--out", str(preview)], check=True,
                       stdout=subprocess.DEVNULL)
        data = preview.read_bytes()
        if len(data) <= 300_000:
            print("MIKSHAT_WEATHER_PREVIEW " + json.dumps({"name": preview.name,
                  "pngBase64": base64.b64encode(data).decode("ascii")}))
if len(images) < 12:
    raise SystemExit("Expected twelve actual weather fixture screenshots; see native test failures")
