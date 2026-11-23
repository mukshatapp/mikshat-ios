#!/usr/bin/env python3
"""Run the update's native map/storage checks and require actual case execution."""

import argparse
from collections import Counter
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys


SUITES = {
    "storage_tests": (
        r"MapFilesDownloader_OfficialSources|StorageDownloadTest_",
        (r"MapFilesDownloader_OfficialSources$", r"StorageDownloadTest_CatalogHashFailurePreservesInstalledMap$"),
    ),
    "mwm_tests": (
        r"ForEachFeatureID_(Test|WorldGeometryScaleContract)$|MikshatOverview_",
        (r"ForEachFeatureID_Test$", r"ForEachFeatureID_WorldGeometryScaleContract$",
         r"MikshatOverview_SaudiIndexedPoints$", r"MikshatOverview_PreservesWorldAndCancellation$"),
    ),
    "indexer_tests": (
        r"classificator_tests\.cpp::|scale_index_reading_tests\.cpp::|visibility_test\.cpp::|Feature_NamedFaydaSelector$",
        (r"Classificator_StableIndex$", r"Classificator_IntermittentWaterwayIndices$", r"Feature_NamedFaydaSelector$"),
    ),
    "style_tests": (
        r".*",
        (r"Classificator_IntermittentWaterwayRules$", r"Classificator_MikshatOutdoorLabels$",
         r"Classificator_MikshatResourcesAndTracks$"),
    ),
    "drape_frontend_tests": (
        r"Mikshat_TwentyKilometreRulerUsesOverviewZoom$|DrawTileScale_DependsOnVisualScale$|Stylist_MikshatNamedFayda$|Stylist_MikshatUnpavedRoads$|ReadCancellation_IndexCancellationPreservesLifecycle$",
        (r"Mikshat_TwentyKilometreRulerUsesOverviewZoom$", r"DrawTileScale_DependsOnVisualScale$",
         r"Stylist_MikshatNamedFayda$", r"Stylist_MikshatUnpavedRoads$",
         r"ReadCancellation_IndexCancellationPreservesLifecycle$"),
    ),
}

CASE_NAME = re.compile(r"[^\s:]+\.cpp::[A-Za-z0-9_]+")
STARTED_CASE = re.compile(r"\bRunning\s+([^\s:]+\.cpp::[A-Za-z0-9_]+)")


def verify(log, expected, returncode):
    started = STARTED_CASE.findall(log)
    counts = Counter(started)
    missing = sorted(set(expected) - counts.keys())
    unexpected = sorted(counts.keys() - set(expected))
    repeated = sorted(name for name, count in counts.items() if count != 1)
    passed = (
        returncode == 0
        and bool(expected)
        and not missing
        and not unexpected
        and not repeated
        and len(re.findall(r"\[OK\]", log)) == len(expected)
        and "All tests passed." in log
        and "[FAILED]" not in log
    )
    return {
        "passed": passed,
        "exitStatus": returncode,
        "expectedCases": expected,
        "executedCases": started,
        "missingCases": missing,
        "unexpectedCases": unexpected,
        "repeatedCases": repeated,
    }


def run_suite(name, build, data, output):
    expression, required = SUITES[name]
    executable = (build / name).resolve()
    writable = (output / "writable" / name).resolve()
    writable.mkdir(parents=True, exist_ok=True)
    arguments = [
        str(executable),
        "--data_path=" + str(data),
        "--user_resource_path=" + str(data),
        "--writable_path=" + str(writable),
    ]
    inventory = subprocess.run(arguments + ["--list_tests"], text=True, capture_output=True, timeout=60, check=True)
    (output / (name + "-inventory.log")).write_text(inventory.stdout + inventory.stderr)
    names = [line.strip() for line in inventory.stdout.splitlines() if CASE_NAME.fullmatch(line.strip())]
    selected = sorted(name for name in names if re.search(expression, name))
    for pattern in required:
        if not any(re.search(pattern, case) for case in selected):
            raise RuntimeError(name + " has no required compiled case matching " + pattern)
    if not selected:
        raise RuntimeError(name + " selected no compiled tests")
    try:
        result = subprocess.run(arguments + ["--filter=" + expression], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900)
        log, returncode = result.stdout, result.returncode
    except subprocess.TimeoutExpired as error:
        log = error.stdout or ""
        if isinstance(log, bytes):
            log = log.decode("utf-8", errors="replace")
        returncode = -1
        log += "\nNative suite exceeded the bounded 900-second timeout.\n"
    (output / (name + ".log")).write_text(log)
    report = verify(log, selected, returncode)
    (output / (name + ".json")).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"suite": name, "expected": len(selected),
                      "executed": len(report["executedCases"]), "passed": report["passed"]}), flush=True)
    if not report["passed"]:
        print(log[-18000:], file=sys.stderr)
        raise RuntimeError(name + " did not execute and pass every selected compiled test exactly once")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--saudi-map-file", type=Path)
    parser.add_argument("--saudi-south-map-file", type=Path)
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    server = root / "tools/python/test_server"
    spec = importlib.util.spec_from_file_location("native_map_fixture", root / "mikshat/tests/update-native/renderer.py")
    fixture_helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture_helper)
    fixture = fixture_helper.prepare_fixture(output, options.saudi_map_file)
    os.environ["MIKSHAT_SAUDI_NORTH_MWM_PATH"] = str(fixture)
    south_fixture = fixture_helper.prepare_fixture(output, options.saudi_south_map_file, fixture_helper.SOUTH_FIXTURE)
    os.environ["MIKSHAT_SAUDI_SOUTH_MWM_PATH"] = str(south_fixture)
    reports = {}
    subprocess.run([sys.executable, str(server / "start_server.py")], check=True, timeout=30)
    try:
        reports["storage_tests"] = run_suite("storage_tests", options.build_dir, root / "data", output)
    finally:
        subprocess.run([sys.executable, str(server / "stop_server.py")], check=True, timeout=30)
    for name in ("mwm_tests", "indexer_tests", "style_tests", "drape_frontend_tests"):
        reports[name] = run_suite(name, options.build_dir, root / "data", output)
    (output / "summary.json").write_text(json.dumps(reports, indent=2) + "\n")


if __name__ == "__main__":
    main()
