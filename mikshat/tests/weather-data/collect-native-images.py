from pathlib import Path
import base64
import json
import shutil
import subprocess
import sys


EXPECTED_IMAGES = frozenset({
    "weather-light-portrait-fixture.png",
    "weather-light-portrait-forecast-fixture.png",
    "weather-dark-portrait-fixture.png",
    "weather-dark-portrait-forecast-fixture.png",
    "weather-light-landscape-fixture.png",
    "weather-light-landscape-forecast-fixture.png",
    "weather-dark-landscape-fixture.png",
    "weather-dark-landscape-forecast-fixture.png",
    "weather-large-type-small-phone-fixture.png",
    "weather-large-type-small-phone-forecast-fixture.png",
    "weather-saved-after-failed-refresh-fixture.png",
    "weather-no-saved-selected-site-fixture.png",
})


def image_manifest(directory):
    names = {image.name for image in directory.glob("weather-*-fixture.png") if image.is_file()}
    return {"nativeWeatherImages": len(names), "names": sorted(names),
            "missing": sorted(EXPECTED_IMAGES - names), "unexpected": sorted(names - EXPECTED_IMAGES),
            "passed": names == EXPECTED_IMAGES,
            "data": "synthetic injected forecasts", "renderer": "actual UIKit views"}


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: collect-native-images.py SIMULATOR_UDID OUTPUT_DIRECTORY")
    udid, output = sys.argv[1:]
    target = Path(output)
    target.mkdir(parents=True, exist_ok=True)
    container = subprocess.check_output(["xcrun", "simctl", "get_app_container", udid,
                                          "com.mikshat.maps.debug", "data"], text=True).strip()
    source = Path(container) / "Documents"
    report = image_manifest(source)
    # Do not let a previous collection leave stale fixture PNGs in the uploaded artifact.
    for image in target.glob("weather-*-fixture.png"):
        if image.is_file():
            image.unlink()
    for name in report["names"]:
        shutil.copy2(source / name, target / name)
    print(json.dumps(report))
    if not report["passed"]:
        raise SystemExit("Expected the exact twelve named weather fixture screenshots; see missing/unexpected names")
    for name in ["weather-light-portrait-fixture.png", "weather-dark-landscape-forecast-fixture.png"]:
        path = target / name
        preview = target / ("preview-" + name)
        subprocess.run(["sips", "-Z", "700", str(path), "--out", str(preview)], check=True,
                       stdout=subprocess.DEVNULL)
        data = preview.read_bytes()
        if len(data) <= 300_000:
            print("MIKSHAT_WEATHER_PREVIEW " + json.dumps({"name": preview.name,
                  "pngBase64": base64.b64encode(data).decode("ascii")}))


if __name__ == "__main__":
    main()
