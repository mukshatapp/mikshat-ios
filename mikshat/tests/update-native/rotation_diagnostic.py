#!/usr/bin/env python3
"""Run the same app-hosted rotation case in fresh automatic/never title-inset hosts.

This diagnostic does not upload an app or claim a production fix. Native failures
remain failures; summaries distinguish unavailable infrastructure and unapplied
probes from an observed A/B difference.
"""

import argparse
from copy import deepcopy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import time
import zipfile

from hang_sampler import BUNDLE, PhaseSampler


CASE = "testSelectedPointStaysAttachedAndResponsiveWhileTheSamePageRotatesRepeatedly"
ROOT = Path(__file__).resolve().parents[3]


def command(args, **kwargs):
    kwargs.setdefault("timeout", 120)
    return subprocess.run(args, text=True, check=True, **kwargs)


def output(args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


def patch_plan(original, mode):
    plan = deepcopy(original)
    count = 0
    def visit(value):
        nonlocal count
        if isinstance(value, dict):
            if value.get("BlueprintName") == "OMapsTests" or str(value.get("TestBundlePath", "")).endswith("/OMapsTests.xctest"):
                args = value.get("CommandLineArguments", [])
                if not isinstance(args, list):
                    raise ValueError("Unexpected native target launch arguments")
                args = [arg for arg in args if arg not in ("-MikshatTitleInsetsNever", "-MikshatRequireRenderer")]
                if "-IsTests" not in args:
                    args.append("-IsTests")
                if mode == "never":
                    args.append("-MikshatTitleInsetsNever")
                value["CommandLineArguments"] = args
                count += 1
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(plan)
    if count != 1:
        raise ValueError("Expected exactly one native OMapsTests target")
    return plan


def classify(passes):
    if len(passes) != 2 or any(item.get("infrastructureError") for item in passes):
        return "infrastructureFailed"
    if any(not item.get("modeApplied") for item in passes):
        return "modeNotApplied"
    automatic, never = passes
    if automatic["passed"] and never["passed"]:
        return "bothPass"
    if automatic.get("hangStackCollected") and not automatic["passed"] and never["passed"]:
        return "autoHangsNeverPasses"
    if not automatic["passed"] and not never["passed"]:
        return "bothFail"
    return "otherFailure"


def native_result(log):
    spec = importlib.util.spec_from_file_location("rotation_native_results", ROOT / "mikshat/tests/weather-data/verify-native-results.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.EXPECTED_CLASSES = {"MikshatMapSceneLayoutTests": 1}
    return module.analyze(log.read_text(errors="replace") if log.exists() else "")


def run_bounded(args, log, sampler, timeout):
    with log.open("w") as stream:
        process = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + timeout
        timed_out = False
        try:
            while process.poll() is None:
                sampler.tick()
                if time.monotonic() >= deadline:
                    timed_out = True
                    # Preserve one final outside-process sample before stopping
                    # the test launcher. Never rely on its MainActor deadline.
                    sampler.tick()
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                    break
                time.sleep(0.5)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            sampler.tick()
    return process.returncode, timed_out


def evaluate_mode(mode, directory, status, timed_out):
    native = native_result(directory / "xcodebuild-test.log")
    phases = []
    journal = directory / "native-samples/phases-seen.jsonl"
    if journal.exists():
        phases = [json.loads(line) for line in journal.read_text().splitlines() if line.strip()]
    expected = "probe.titleInsetsNever.applied" if mode == "never" else "probe.titleInsetsAutomatic.observed"
    behavior = 2 if mode == "never" else 0
    applied = any(item.get("phase") == expected and item.get("behavior") == behavior for item in phases)
    samples = list((directory / "native-samples").glob("sample-*.txt"))
    monitor_path = directory / "native-samples/monitor.jsonl"
    monitor = [json.loads(line) for line in monitor_path.read_text().splitlines() if line.strip()] if monitor_path.exists() else []
    synchronous_samples = [item for item in monitor if item.get("result") == "sampled"
                           and str(item.get("phase", {}).get("phase", "")).endswith(".begin")]
    native_timeout = timed_out or any(re.search(r"exceeded execution time|test.*timed? out|test timeout", line, re.I)
                                     for line in native.get("testFailures", []))
    result = {"mode": mode, "commandExitStatus": status, "timedOut": timed_out,
              "modeApplied": applied, "phasesObserved": len(phases),
              "localeConfirmed": any(str(item.get("language", "")).startswith("ar")
                                     and item.get("direction") == "RTL" for item in phases),
              "lastPhase": phases[-1] if phases else None,
              "nativeStackCollected": any(path.stat().st_size > 0 for path in samples),
              "hangStackCollected": native_timeout and bool(synchronous_samples),
              "stackReviewRequired": bool(samples),
              "nativeExecution": native,
              "passed": status == 0 and not timed_out and applied and native["passed"]
                        and any(str(item.get("language", "")).startswith("ar")
                                and item.get("direction") == "RTL" for item in phases),
              "scope": "UIKit-only simulator probe; no physical-device, real-feature or Metal assertion"}
    (directory / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    # Compiled objects and xcresult bundles stay outside the compact artifact.
    derived = ROOT / "build/RotationDiagnosticDerivedData"
    results = []
    simulators = []
    summary = {"productionFixVerified": False, "passes": results,
               "scope": "Diagnostic A/B title-inset probe on an isolated iPhone simulator; no upload"}
    try:
        toolchain = output(["xcodebuild", "-version"])
        (destination / "toolchain.txt").write_text(toolchain + "\n")
        if "Xcode 27.0" not in toolchain:
            raise RuntimeError("This diagnostic requires the selected Xcode 27.0 host")
        runtimes = json.loads(output(["xcrun", "simctl", "list", "--json", "runtimes"]))["runtimes"]
        matching = [runtime for runtime in runtimes if runtime.get("isAvailable")
                    and runtime.get("version") == "27.0" and "iOS" in runtime.get("identifier", "")]
        (destination / "runtimes.json").write_text(json.dumps(runtimes, indent=2) + "\n")
        if len(matching) != 1:
            raise RuntimeError("Exactly one installed, available iOS 27.0 runtime is required")
        runtime = matching[0]["identifier"]
        for mode in ("automatic", "never"):
            udid = output(["xcrun", "simctl", "create", "Mikshat rotation " + mode,
                           "com.apple.CoreSimulator.SimDeviceType.iPhone-16", runtime])
            simulators.append(udid)
        command(["xcrun", "simctl", "boot", simulators[0]])
        command(["xcrun", "simctl", "bootstatus", simulators[0], "-b"], timeout=180)
        common = ["-workspace", os.environ.get("XCODE_WORKSPACE", "xcode/omim.xcworkspace"),
                  "-scheme", os.environ.get("XCODE_SCHEME", "OMaps"), "-configuration", "Debug",
                  "-sdk", "iphonesimulator", "-derivedDataPath", str(derived),
                  "-testLanguage", "ar", "-testRegion", "SA", "ARCHS=" + os.uname().machine,
                  "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"]
        with (destination / "xcodebuild-build.log").open("w") as stream:
            command(["xcodebuild", "build-for-testing", *common, "-destination", "id=" + simulators[0]],
                    stdout=stream, stderr=subprocess.STDOUT, timeout=5400)
        products = derived / "Build/Products"
        plans = []
        for path in products.glob("*.xctestrun"):
            try:
                plan = plistlib.loads(path.read_bytes())
                patch_plan(plan, "automatic")
                plans.append((path, plan))
            except ValueError:
                continue
        if len(plans) != 1:
            raise RuntimeError("Expected exactly one compiled native OMapsTests plan")
        apps = [app for app in (products / "Debug-iphonesimulator").glob("*.app")
                if plistlib.loads((app / "Info.plist").read_bytes()).get("CFBundleIdentifier") == BUNDLE]
        if len(apps) != 1:
            raise RuntimeError("Expected exactly one compiled Debug app host")
        for mode, udid in zip(("automatic", "never"), simulators):
            directory = destination / mode
            directory.mkdir()
            if mode == "never":
                command(["xcrun", "simctl", "boot", udid])
                command(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=180)
            command(["xcrun", "simctl", "install", udid, str(apps[0])])
            command(["xcrun", "simctl", "privacy", udid, "grant", "location", BUNDLE])
            command(["xcrun", "simctl", "location", udid, "set", "26.2317333333,44.9453"])
            plan_path = products / ("MikshatTitleInsets-" + mode + ".xctestrun")
            plan_path.write_bytes(plistlib.dumps(patch_plan(plans[0][1], mode)))
            sampler = PhaseSampler(udid, directory / "native-samples")
            test = ["xcodebuild", "test-without-building", "-xctestrun", str(plan_path),
                    "-destination", "id=" + udid, "-destination-timeout", "60",
                    "-resultBundlePath", str(ROOT / "build" / ("RotationDiagnostic-" + mode + ".xcresult")),
                    "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                    "-testLanguage", "ar", "-testRegion", "SA",
                    "-default-test-execution-time-allowance", "60", "-maximum-test-execution-time-allowance", "60",
                    "-only-testing:OMapsTests/MikshatMapSceneLayoutTests/" + CASE,
                    "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"]
            status, timed_out = run_bounded(test, directory / "xcodebuild-test.log", sampler, 180)
            results.append(evaluate_mode(mode, directory, status, timed_out))
            command(["xcrun", "simctl", "shutdown", udid])
        summary["classification"] = classify(results)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        if getattr(error, "cmd", [])[:2] == ["xcodebuild", "build-for-testing"]:
            summary.update(classification="buildFailed", buildError=str(error))
            build_log = destination / "xcodebuild-build.log"
            if build_log.exists():
                lines = build_log.read_text(errors="replace").splitlines()
                errors = [line for line in lines if ": error:" in line or "fatal error:" in line]
                print("Build-for-testing failed. Compiler diagnostics:", flush=True)
                for line in (errors[:40] or lines[-40:]):
                    print(line, flush=True)
        else:
            summary.update(classification="infrastructureFailed", infrastructureError=str(error))
    finally:
        for udid in simulators:
            for operation in ("shutdown", "delete"):
                try:
                    subprocess.run(["xcrun", "simctl", operation, udid], text=True, capture_output=True, timeout=30)
                except (OSError, subprocess.TimeoutExpired) as error:
                    summary.setdefault("cleanupErrors", []).append(str(error))
        summary["allNativeCasesPassed"] = len(results) == 2 and all(item["passed"] for item in results)
        (destination / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        archive = destination / "rotation-diagnostics.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for path in destination.rglob("*"):
                if path.is_file() and path != archive:
                    package.write(path, str(path.relative_to(destination)))
        print(json.dumps(summary), flush=True)
    if not summary["allNativeCasesPassed"]:
        raise SystemExit("The diagnostic did not establish two passing native cases; inspect the classification and native stacks")


if __name__ == "__main__":
    main()
