#!/usr/bin/env python3
"""Run the CarPlay app-hosted regressions on one isolated iPhone simulator.

This checks UIKit, route state and location fixtures. It does not claim a real
CarPlay display connection, signed entitlement verification or vehicle testing.
"""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "mikshat/tests/update-native"))
import rotation_diagnostic as native


CARPLAY_CLASSES = {
    "CarPlayServiceTests": 26,
    "CarPlaySceneDelegateTests": 2,
    "CarPlayManeuverMapperTests": 4,
    "CarPlayTripMetricsTests": 13,
    "MapTemplateBuilderTests": 7,
    "CarPlayRouterSharedSessionTests": 10,
    "CarPlaySharedGuidanceTests": 8,
}
RESPONSIVE_CLASS = "MikshatResponsiveNavigationTests"


def required_cases():
    cases = {}
    directory = ROOT / "iphone/Maps/Tests/Classes/CarPlay"
    for name, minimum in CARPLAY_CLASSES.items():
        source = (directory / (name + ".swift")).read_text()
        if not re.search(r"\bclass\s+" + name + r"\s*:\s*XCTestCase\b", source):
            raise ValueError("Missing XCTest class: " + name)
        methods = re.findall(r"^\s+func\s+(test\w+)\s*\(", source, re.MULTILINE)
        if len(methods) < minimum or len(methods) != len(set(methods)):
            raise ValueError("Incomplete or repeated source cases in " + name)
        cases[name] = methods
    source = (ROOT / "iphone/Maps/Tests/UI/SearchOnMapTests/MikshatResponsiveUITests.swift").read_text()
    match = re.search(r"^final class " + RESPONSIVE_CLASS + r": XCTestCase \{(.*?)^\}",
                      source, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError("Missing phone navigation regression class")
    methods = re.findall(r"^\s+func\s+(test\w+)\s*\(", match[1], re.MULTILINE)
    if len(methods) != 4 or len(methods) != len(set(methods)):
        raise ValueError("Expected all four phone navigation regression cases")
    cases[RESPONSIVE_CLASS] = methods
    # The two active-Metal road-entry cases need the large map fixtures and have
    # their own gate; keep the four ordinary phone entry regressions here.
    cases["MikshatRoutingEntryTests"] = list(native.PRODUCTION_CASES["MikshatRoutingEntryTests"])
    return cases


def native_target(plan):
    found = []
    def visit(value):
        if isinstance(value, dict):
            if value.get("BlueprintName") == "OMapsTests" or str(value.get("TestBundlePath", "")).endswith("/OMapsTests.xctest"):
                found.append(value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(plan)
    if len(found) != 1:
        raise ValueError("Expected exactly one native OMapsTests target")
    return found[0]


def localized_plan(plan, language, region):
    result = native.patch_plan(plan, "automatic", production=True, language=language, region=region)
    target = native_target(result)
    arguments = [argument for argument in target["CommandLineArguments"] if argument != native.PRODUCTION_FLAG]
    arguments += ["-MikshatCarPlayTestLanguage", language]
    target["CommandLineArguments"] = arguments
    return result


def analyze(log, cases):
    spec = importlib.util.spec_from_file_location("carplay_native_results", ROOT / "mikshat/tests/weather-data/verify-native-results.py")
    verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verifier)
    verifier.EXPECTED_CLASSES = {name: len(methods) for name, methods in cases.items()}
    text = log.read_text(errors="replace") if log.exists() else ""
    result = verifier.analyze(text)
    expected = {(name, method) for name, methods in cases.items() for method in methods}
    observed = {identity for event in verifier.CASE_EVENT.finditer(text)
                if (identity := verifier.case_identity(event[2])) is not None}
    result["missingCases"] = sorted(f"{name}.{method}" for name, method in expected - observed)
    result["unexpectedCases"] = sorted(f"{name}.{method}" for name, method in observed - expected)
    result["passed"] = result["passed"] and observed == expected
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", choices=("ar", "en"), required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--derived-data", type=Path, default=ROOT / "build/SearchDerivedData")
    options = parser.parse_args()
    directory = options.output_dir.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    region = "SA" if options.language == "ar" else "US"
    udid = None
    summary = {"passed": False, "language": options.language, "region": region,
               "scope": "App-hosted CarPlay and phone regressions on an isolated iPhone simulator; no physical CarPlay or entitlement assertion"}
    try:
        cases = required_cases()
        (directory / "required-cases.json").write_text(json.dumps(cases, indent=2) + "\n")
        toolchain = native.output(["xcodebuild", "-version"])
        (directory / "toolchain.txt").write_text(toolchain + "\n")
        if "Xcode 27.0" not in toolchain:
            raise RuntimeError("The CarPlay gate requires Xcode 27.0")
        runtimes = json.loads(native.output(["xcrun", "simctl", "list", "--json", "runtimes"]))["runtimes"]
        matching = [runtime for runtime in runtimes if runtime.get("isAvailable")
                    and runtime.get("version") == "27.0" and "iOS" in runtime.get("identifier", "")]
        if len(matching) != 1:
            raise RuntimeError("Exactly one available iOS 27.0 runtime is required")
        udid = native.output(["xcrun", "simctl", "create", "Mikshat CarPlay " + options.language,
                              "com.apple.CoreSimulator.SimDeviceType.iPhone-16", matching[0]["identifier"]])
        (directory / "simulator.json").write_text(json.dumps({"udid": udid, "runtime": matching[0]}, indent=2) + "\n")
        native.command(["xcrun", "simctl", "boot", udid], timeout=60)
        native.command(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=180)
        common = ["-workspace", "xcode/omim.xcworkspace", "-scheme", "OMaps", "-configuration", "Debug",
                  "-sdk", "iphonesimulator", "-destination", "id=" + udid,
                  "-destination-timeout", "120", "-derivedDataPath", str(options.derived_data),
                  "-testLanguage", options.language, "-testRegion", region,
                  "ARCHS=" + os.uname().machine, "ONLY_ACTIVE_ARCH=YES",
                  "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"]
        with (directory / "xcodebuild-build.log").open("w") as log:
            native.command(["xcodebuild", "build-for-testing", *common,
                            "-resultBundlePath", str(directory / "Build.xcresult")],
                           stdout=log, stderr=subprocess.STDOUT, timeout=3300)
        products = options.derived_data / "Build/Products"
        plans = []
        for path in products.glob("*.xctestrun"):
            if path.name.startswith(("MikshatTitleInsets-", "MikshatRenderer", "MikshatCarPlay-")):
                continue
            plan = plistlib.loads(path.read_bytes())
            try:
                native_target(plan)
            except ValueError:
                continue
            plans.append(plan)
        if len(plans) != 1:
            raise RuntimeError("Expected exactly one original compiled OMapsTests plan")
        plan = localized_plan(plans[0], options.language, region)
        plan_path = products / ("MikshatCarPlay-" + options.language + ".xctestrun")
        plan_path.write_bytes(plistlib.dumps(plan))
        (directory / "test-launch.json").write_text(json.dumps({
            "language": options.language, "region": region,
            "arguments": native_target(plan)["CommandLineArguments"]}, indent=2) + "\n")
        filters = [f"-only-testing:OMapsTests/{name}/{method}"
                   for name, methods in cases.items() for method in methods]
        command = ["xcodebuild", "test-without-building", "-xctestrun", str(plan_path),
                   "-destination", "id=" + udid, "-destination-timeout", "120",
                   "-resultBundlePath", str(directory / "Tests.xcresult"),
                   "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                   "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120",
                   "-maximum-test-execution-time-allowance", "180", *filters,
                   "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"]
        log_path = directory / "xcodebuild-test.log"
        with log_path.open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=1200)
        summary["commandExitStatus"] = result.returncode
        summary["nativeExecution"] = analyze(log_path, cases)
        summary["passed"] = result.returncode == 0 and summary["nativeExecution"]["passed"]
        summary["classification"] = "nativeTestsPassed" if summary["passed"] else "nativeTestsFailed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        summary["error"] = str(error)
        summary["classification"] = "buildFailed" if getattr(error, "cmd", [])[:2] == ["xcodebuild", "build-for-testing"] else "infrastructureFailed"
        if summary["classification"] == "buildFailed":
            log = directory / "xcodebuild-build.log"
            if log.exists():
                lines = log.read_text(errors="replace").splitlines()
                diagnostics = [line for line in lines if ": error:" in line or "fatal error:" in line]
                for line in diagnostics[:40] or lines[-40:]:
                    print(line, flush=True)
    finally:
        if udid is not None:
            for operation in ("shutdown", "delete"):
                try:
                    subprocess.run(["xcrun", "simctl", operation, udid], text=True, capture_output=True, timeout=30)
                except (OSError, subprocess.TimeoutExpired) as error:
                    summary.setdefault("cleanupErrors", []).append(str(error))
        (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary), flush=True)
    if not summary["passed"]:
        raise SystemExit("CarPlay native verification did not establish all required tests passing")


if __name__ == "__main__":
    main()
