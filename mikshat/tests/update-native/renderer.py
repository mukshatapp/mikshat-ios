#!/usr/bin/env python3
"""Prepare and verify the opt-in normal-renderer rotation pass on an isolated simulator."""

import argparse
from copy import deepcopy
import importlib.util
import json
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import struct
import subprocess
import time


ROOT = Path(__file__).resolve().parents[3]
BUNDLE = "com.mikshat.maps.debug"
CASE = "testSelectedPointStaysAttachedAndResponsiveWhileTheSamePageRotatesRepeatedly"
CASES = {
    "MikshatMapSceneLayoutTests": (CASE,),
    "MikshatVehicleRoutingEntryTests": (
        "testMapSelectionGoToBuildsVehicleRouteWithSaudiMapAndRenderer",
        "testSearchSelectionGoToBuildsVehicleRouteWithSaudiMapAndRenderer"),
}
FIXTURE = {
    "country": "Saudi Arabia_North",
    "version": 260714,
    "size": 71760131,
    "catalogHash": "i5mCFqnSjXOf",
    "sha256": "6cd35fcb5b2bcd8c0ce5f9249426126c1a3c56635033c07fde855b9316651fe0",
    "url": "https://cdn.organicmaps.app/maps/260714/Saudi%20Arabia_North.mwm",
}
SOUTH_FIXTURE = {
    "country": "Saudi Arabia_South",
    "version": 260714,
    "size": 69904708,
    "catalogHash": "gl/FyL+gwsOW",
    "sha256": "7591a4c97628994b04856b84988ea6259bda4bf4c194702ef39817f02d484425",
    "url": "https://cdn.organicmaps.app/maps/260714/Saudi%20Arabia_South.mwm",
}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_fixture(path, fixture_info=FIXTURE):
    inspector = load_module("renderer_mwm_inspector", ROOT / "tools/python/mikshat/inspect_mwm.py")
    result = inspector.inspect(path, expected_version=fixture_info["version"], expected_size=fixture_info["size"], country=True)
    if result["sha256"] != fixture_info["sha256"]:
        raise ValueError("The official Saudi map differs from the independently verified fixture SHA-256")
    return result


def prepare_fixture(output, map_file=None, fixture_info=FIXTURE):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    countries = json.loads((ROOT / "data/countries.json").read_text())
    if countries["v"] != fixture_info["version"]:
        raise ValueError("Update the renderer fixture explicitly before testing another map catalog")

    def entries(node):
        yield node
        for child in node.get("g", []):
            yield from entries(child)

    country = [entry for entry in entries(countries) if entry.get("id") == fixture_info["country"]]
    if len(country) != 1 or country[0].get("s") != fixture_info["size"] or country[0].get("h") != fixture_info["catalogHash"]:
        raise ValueError("The fixture must match this build's exact country catalog entry")
    maps = output / "fixture"
    maps.mkdir(exist_ok=True)
    fixture = maps / (fixture_info["country"] + ".mwm")
    if map_file:
        shutil.copy2(map_file, fixture)
    else:
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--connect-timeout", "20",
                        "--max-time", "240", "--output", str(fixture), fixture_info["url"]], check=True, timeout=250)
    inspection = validate_fixture(fixture, fixture_info)
    name = "official-map-inspection.json" if fixture_info == FIXTURE else "official-map-inspection-south.json"
    (output / name).write_text(json.dumps(inspection, indent=2) + "\n")
    return fixture


def patch_plan(plan):
    candidate = deepcopy(plan)
    patched = []

    def visit(value):
        if isinstance(value, dict):
            if value.get("BlueprintName") == "OMapsTests" or str(value.get("TestBundlePath", "")).endswith("/OMapsTests.xctest"):
                arguments = value.get("CommandLineArguments", [])
                if not isinstance(arguments, list) or not all(isinstance(item, str) for item in arguments):
                    raise ValueError("Unexpected OMapsTests launch argument format")
                filtered = []
                offset = 0
                while offset < len(arguments):
                    argument = arguments[offset]
                    if argument in ("-AppleLanguages", "-AppleLocale", "-AlohalyticsInstallationId"):
                        if offset + 1 >= len(arguments):
                            raise ValueError("A paired launch argument has no value")
                        offset += 2
                        continue
                    if argument not in ("-IsTests", "-MikshatRequireRenderer"):
                        filtered.append(argument)
                    offset += 1
                filtered += ["-MikshatRequireRenderer", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA",
                             "-AlohalyticsInstallationId", "I:MikshatRotationRendererDiagnostics"]
                value["CommandLineArguments"] = filtered
                patched.append(filtered)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(candidate)
    if not patched:
        raise ValueError("No OMapsTests target exists in this xctestrun plan")
    return candidate, patched


def simctl(*arguments, check=True):
    return subprocess.run(["xcrun", "simctl", *arguments], check=check, text=True, capture_output=True, timeout=60)


def prepare(options):
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    products = options.products.resolve()
    plans = []
    for path in products.glob("*.xctestrun"):
        if path.name.startswith("MikshatRenderer"):
            continue
        try:
            plan, targets = patch_plan(plistlib.loads(path.read_bytes()))
            plans.append((path, plan, targets))
        except ValueError as error:
            if str(error).startswith("No OMapsTests target"):
                continue
            raise
    if len(plans) != 1:
        raise ValueError("Expected one native OMapsTests plan, found " + str(len(plans)))
    original, plan, targets = plans[0]
    target = products / "MikshatRendererRotationArabic.xctestrun"
    target.write_bytes(plistlib.dumps(plan))

    fixture = prepare_fixture(output, options.map_file)

    apps = [app for app in (products / "Debug-iphonesimulator").glob("*.app")
            if plistlib.loads((app / "Info.plist").read_bytes()).get("CFBundleIdentifier") == BUNDLE]
    if len(apps) != 1:
        raise ValueError("Expected one built native Debug test host")
    previous = simctl("get_app_container", options.udid, BUNDLE, "data", check=False)
    old = previous.stdout.strip() if previous.returncode == 0 else None
    simctl("terminate", options.udid, BUNDLE, check=False)
    simctl("uninstall", options.udid, BUNDLE)
    simctl("install", options.udid, str(apps[0]))
    container = Path(simctl("get_app_container", options.udid, BUNDLE, "data").stdout.strip())
    documents = container / "Documents"
    catalog = FIXTURE["version"]
    destination = documents / str(catalog) / fixture.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fixture, destination)
    latitude, longitude = 26 + 13.904 / 60, 44 + 56.718 / 60
    mercator_y = math.degrees(math.log(math.tan(math.pi / 4 + math.radians(latitude) / 2)))
    viewport = (longitude, mercator_y, 0, -0.1, -0.2, 0.1, 0.2)
    (documents / "settings.ini").write_text("ScreenClipRect=" + " ".join(format(v, ".12g") for v in viewport) + "\n")
    simctl("privacy", options.udid, "grant", "location", BUNDLE)
    simctl("location", options.udid, "set", str(latitude) + "," + str(longitude))
    report = {"nativePlan": str(original), "rendererPlan": str(target), "arguments": targets,
              "oldContainer": old, "isolatedContainer": str(container), "officialMap": FIXTURE,
              "installedMap": str(destination), "selectedCoordinate": [latitude, longitude],
              "scope": "Normal Drape with verified Saudi map backdrop and synthetic point selection; isolated Debug simulator only"}
    (output / "launch.json").write_text(json.dumps(report, indent=2) + "\n")
    environment = os.environ.get("GITHUB_ENV")
    if environment:
        with open(environment, "a") as stream:
            stream.write("MIKSHAT_ROTATION_RENDERER_XCTESTRUN=" + str(target) + "\n")
    print(json.dumps(report), flush=True)


def capture(options):
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    stopping = False

    def stop(_signal, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    deadline = time.monotonic() + 240
    iteration = 0
    with (output / "captures.jsonl").open("w") as manifest:
        while not stopping and time.monotonic() < deadline:
            iteration += 1
            path = output / ("renderer-screen-" + str(iteration).zfill(4) + ".png")
            record = {"startedAt": time.time(), "file": str(path)}
            try:
                result = subprocess.run(["xcrun", "simctl", "io", options.udid, "screenshot", str(path)],
                                        text=True, capture_output=True, timeout=10)
                record.update(exitStatus=result.returncode, output=result.stdout + result.stderr)
                if result.returncode == 0:
                    header = path.read_bytes()[:24]
                    if header[:8] != b"\x89PNG\r\n\x1a\n":
                        raise ValueError("simctl did not produce a PNG")
                    record["width"], record["height"] = struct.unpack(">II", header[16:24])
            except (subprocess.TimeoutExpired, ValueError, OSError) as error:
                record.update(exitStatus=None, error=str(error))
            record["completedAt"] = time.time()
            manifest.write(json.dumps(record) + "\n")
            manifest.flush()
            if not stopping:
                time.sleep(0.75)


def verify_records(records, captures):
    expected = [(cycle, orientation) for cycle in range(3) for orientation in (3, 1, 4, 1)]
    rotations = [r for r in records if r.get("event") == "rotated"]
    order = [(r.get("cycle"), r.get("orientation")) for r in rotations]
    states = all(r.get("rendererReady") is True and r.get("graphicsReady") is True
                 and r.get("active") is True and r.get("windowAttached") is True
                 and r.get("layer") == "CAMetalLayer" and r.get("direction") == "RTL"
                 and str(r.get("language", "")).startswith("ar") for r in records)
    geometry = all((r.get("width", 0) > r.get("height", 0) > 0) if r.get("orientation") in (3, 4)
                   else (r.get("height", 0) > r.get("width", 0) > 0) for r in rotations)
    event_order = [r.get("event") for r in records] == ["ready"] + ["rotated"] * 12 + ["completed"]
    screenshots = []
    if event_order:
        screenshots = [r for r in captures if r.get("exitStatus") == 0 and r.get("width", 0) > 0
                       and r.get("height", 0) > 0 and records[0]["timestamp"] <= r["startedAt"] <= records[-1]["timestamp"]]
    return {"passed": states and geometry and event_order and order == expected and bool(screenshots),
            "records": len(records), "rotationOrder": order, "expectedRotationOrder": expected,
            "statesValid": states, "geometryValid": geometry, "eventOrderValid": event_order,
            "screenshotsDuringTest": len(screenshots),
            "scope": "Active Metal simulator, verified Saudi map backdrop, synthetic selected point; not a physical-device or real-stream identity claim"}


def native_result(log):
    native = load_module("rotation_native_results", ROOT / "mikshat/tests/weather-data/verify-native-results.py")
    native.EXPECTED_CLASSES = {name: len(methods) for name, methods in CASES.items()}
    log = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", log)
    result = native.analyze(log)
    expected = {(name, method) for name, methods in CASES.items() for method in methods}
    observed = {identity for event in native.CASE_EVENT.finditer(log)
                if (identity := native.case_identity(event[2])) is not None}
    result["missingCases"] = sorted(f"{name}.{method}" for name, method in expected - observed)
    result["unexpectedCases"] = sorted(f"{name}.{method}" for name, method in observed - expected)
    result["passed"] = result["passed"] and observed == expected
    return result


def verify(options):
    output = options.output_dir.resolve()
    container = Path(simctl("get_app_container", options.udid, BUNDLE, "data").stdout.strip())
    source = container / "Documents/mikshat-renderer-rotation.jsonl"
    shutil.copy2(source, output / "coverage.jsonl")
    records = [json.loads(line) for line in source.read_text().splitlines() if line.strip()]
    captures = [json.loads(line) for line in (output / "screenshots/captures.jsonl").read_text().splitlines() if line.strip()]
    captures = [entry for entry in captures if Path(entry.get("file", "")).is_file()
                and Path(entry["file"]).read_bytes()[:8] == b"\x89PNG\r\n\x1a\n"]
    report = verify_records(records, captures)
    report["nativeExecution"] = native_result((output / "xcodebuild-renderer.log").read_text(errors="replace"))
    report["testStepOutcome"] = options.test_outcome
    report["passed"] = report["passed"] and report["nativeExecution"]["passed"] and options.test_outcome == "success"
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    if not report["passed"]:
        raise SystemExit("Active Metal, the exact twelve rotations, screenshots, and all three native cases must pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    preparation = commands.add_parser("prepare")
    preparation.add_argument("--products", type=Path, required=True)
    preparation.add_argument("--map-file", type=Path)
    for name in ("capture", "verify"):
        commands.add_parser(name)
    commands.choices["verify"].add_argument("--test-outcome", required=True)
    for command in commands.choices.values():
        command.add_argument("--udid", required=True)
        command.add_argument("--output-dir", type=Path, required=True)
    options = parser.parse_args()
    {"prepare": prepare, "capture": capture, "verify": verify}[options.command](options)


if __name__ == "__main__":
    main()
