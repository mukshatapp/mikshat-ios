#!/usr/bin/env python3
"""Run isolated layout probes or the production feature regression suite.

Production builds once, then runs focused app-hosted cases on fresh Arabic/English
phone/tablet simulators without runtime probes. Phones verify actual scene rotation;
tablets verify component resizing without requiring a physical-orientation driver.
Diagnostic mode keeps the three single-case A/B hosts. Neither mode uploads an app
or claims physical-device proof; unavailable infrastructure remains a failure.
"""

import argparse
import codecs
from copy import deepcopy
import importlib.util
from itertools import islice
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import tempfile
import time
import zipfile

from hang_sampler import BUNDLE, PhaseSampler, captured_text, stack_has_frames


CASE = "testSelectedPointStaysAttachedAndResponsiveWhileTheSamePageRotatesRepeatedly"
ROOT = Path(__file__).resolve().parents[3]
MODES = {
    "automatic": (None, "probe.titleInsetsAutomatic.observed"),
    "fixed-title": ("-MikshatFixedTitleHeight", "probe.fixedTitleHeight.applied"),
    "preview-insets": ("-MikshatPreviewInsetsNever", "probe.previewInsetsNever.applied"),
}
PRODUCTION_FLAG = "-MikshatVerifyProductionRotation"
PROBE_FLAGS = {"-MikshatTitleInsetsNever", "-MikshatRequireRenderer", "-MikshatFixedTitleHeight",
               "-MikshatPreviewInsetsNever", "-MikshatRotationDiagnostics"}
ROTATIONS = [(cycle, orientation) for cycle in range(3) for orientation in (3, 1, 4, 1)]
PRODUCTION_CASES = {
    "MikshatMapSceneLayoutTests": (CASE,),
    "MikshatResponsivePresentationTests": (
        "testSearchSheetAndNativeHeaderStayCenteredWhenTheContainerRotates",),
    "MikshatResponsivePlaceCoordinatesTests": (
        "testInformationEndsWithOneAccessibleWeatherActionAndNoDuplicateCoordinateRows",),
    "MikshatSupplementaryMapsTests": (
        "testEveryBundledMapCanActivateDeactivateAndReactivateWithoutDeletingItsFile",
        "testSelectionRestoresOnlyKnownMapsAndOnlyOnce",
        "testSuccessfulTogglePersistsAndDisabledMapStaysOffAfterRelaunch",
        "testFailedActivationAndDeactivationDoNotChangeSelection"),
    "SearchHistoryOnlyTests": (
        "test_LegacyCategoryAndInvalidIndicesOpenDirectHistoryWithoutPager",
        "test_HistorySelectionAndCoordinateDirectionTargetRemainIntact",
        "test_SameNameLocationsKeepTheirOwnCoordinatesAndSurviveReload",
        "test_LegacyNameShowsResolutionHintWhileKnownCoordinatesOpenDirectly",
        "test_LocationStoreRestoresNamesAndDistinctPointsAndPromotesTheSamePoint",
        "test_CorruptAndOutOfRangeLocationsDoNotOpenAnInventedPoint",
        "test_DisabledHistoryDoesNotSaveSelectedLocations",
        "test_CoreHistorySelectionShowsTheStoredPointAndTitle",
        "test_RotatedHistoryAccessoryKeepsFixedGeometryThroughTableLayoutAndReuse",
        "test_EmptyAndDisabledHistoryStayEmptyWithoutFallingBackToCategories",
        "test_ClearHistoryStillClearsQueriesAndSavedDirectionTargets",
        "test_PresentationInsetAndVerticalScrollingReachTheSearchSheet",
        "test_PlaceInformationEndsAtWeatherActionAfterUnchangedCoordinates",
        "test_ShortPlacePageDragStopsAtItsContentEnd"),
    "SearchOnMapTests": (
        "test_GivenSavedHistoryPoint_WhenSelected_ThenOpensItWithoutSearchingOrUsingAResultIndex",
        "test_GivenLegacyHistoryQuery_WhenResultIsChosen_ThenLaterTapOpensThatPointWithoutSearchingAgain",
        "test_GivenSavedHistoryPointInRoutePicker_WhenSelected_ThenSelectsThatPointWithoutMapSearch"),
}
PRODUCTION_PROFILES = tuple(
    {"id": f"{family}-{language}", "family": family, "language": language,
     "region": "SA" if language == "ar" else "US"}
    for family in ("phone", "tablet") for language in ("ar", "en")
)


def selected_cases(production, family="phone"):
    if not production:
        return {"MikshatMapSceneLayoutTests": (CASE,)}
    # Actual iPad scene rotation needs a separate public physical-orientation
    # driver and full-screen Settings setup. This gate instead exercises the
    # real search component in portrait/landscape container sizes on tablets.
    return {name: methods for name, methods in PRODUCTION_CASES.items()
            if family != "tablet" or name != "MikshatMapSceneLayoutTests"}


def testing_filters(production, family="phone"):
    return [f"-only-testing:OMapsTests/{name}/{method}"
            for name, methods in selected_cases(production, family).items() for method in methods]


def device_type(family, available):
    if family == "phone":
        target = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"
        if any(item.get("identifier") == target for item in available):
            return target
    elif family == "tablet":
        # Use an installed 13-inch iPad definition rather than assuming a
        # particular memory/model suffix across Xcode point releases.
        candidates = [item for item in available if "iPad" in item.get("name", "")
                      and "13-inch" in item.get("name", "")]
        if candidates:
            return sorted(candidates, key=lambda item: item["identifier"])[0]["identifier"]
    raise RuntimeError("No supported installed simulator device type for " + family)


def command(args, **kwargs):
    kwargs.setdefault("timeout", 120)
    return subprocess.run(args, text=True, check=True, **kwargs)


def output(args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


def patch_plan(original, mode, production=False):
    if mode not in MODES or (production and mode != "automatic"):
        raise ValueError("Unknown layout diagnostic mode")
    plan = deepcopy(original)
    count = 0
    def visit(value):
        nonlocal count
        if isinstance(value, dict):
            if value.get("BlueprintName") == "OMapsTests" or str(value.get("TestBundlePath", "")).endswith("/OMapsTests.xctest"):
                args = value.get("CommandLineArguments", [])
                if not isinstance(args, list):
                    raise ValueError("Unexpected native target launch arguments")
                args = [arg for arg in args if arg not in PROBE_FLAGS | {PRODUCTION_FLAG}]
                if "-IsTests" not in args:
                    args.append("-IsTests")
                if production:
                    args.append(PRODUCTION_FLAG)
                else:
                    args.append("-MikshatRotationDiagnostics")
                    if MODES[mode][0]:
                        args.append(MODES[mode][0])
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


def classify(passes, production=False):
    expected = {profile["id"] for profile in PRODUCTION_PROFILES} if production else set(MODES)
    observed = {item.get("profile") if production else item.get("mode") for item in passes}
    if (len(passes) != len(expected) or observed != expected
            or any(item.get("infrastructureError") or item.get("nativeExecution", {}).get("casesStarted") == 0
                   for item in passes)):
        return "infrastructureFailed"
    if any(not item.get("modeApplied") for item in passes):
        return "modeNotApplied"
    if production:
        return "productionLayoutSimulatorPassed" if all(item["passed"] for item in passes) else "productionLayoutSimulatorFailed"
    by_mode = {item["mode"]: item for item in passes}
    if all(item["passed"] for item in passes):
        return "allPass"
    if not by_mode["automatic"]["passed"] and any(by_mode[mode]["passed"] for mode in MODES if mode != "automatic"):
        return "baselineFailsProbePasses"
    if not any(item["passed"] for item in passes):
        return "allFail"
    return "otherFailure"


def native_result(log, production=False, family="phone"):
    spec = importlib.util.spec_from_file_location("rotation_native_results", ROOT / "mikshat/tests/weather-data/verify-native-results.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    cases = selected_cases(production, family)
    module.EXPECTED_CLASSES = {name: len(methods) for name, methods in cases.items()}
    text = log.read_text(errors="replace") if log.exists() else ""
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    result = module.analyze(text)
    expected = {(name, method) for name, methods in cases.items() for method in methods}
    observed = {identity for event in module.CASE_EVENT.finditer(text)
                if (identity := module.case_identity(event[2])) is not None}
    result["missingCases"] = sorted(f"{name}.{method}" for name, method in expected - observed)
    result["unexpectedCases"] = sorted(f"{name}.{method}" for name, method in observed - expected)
    result["passed"] = result["passed"] and observed == expected
    return result


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


def evaluate_mode(mode, directory, status, timed_out, production=False, language="ar", profile=None, family="phone"):
    log = directory / "xcodebuild-test.log"
    native = native_result(log, production, family)
    expected_direction = "RTL" if language == "ar" else "LTR"
    phases = []
    journal = directory / "native-samples/phases-seen.jsonl"
    if journal.exists():
        phases = [json.loads(line) for line in journal.read_text().splitlines() if line.strip()]
    candidates = [item for item in phases if item.get("phase") == MODES[mode][1]]
    layout_profiles = []
    if production and log.exists():
        text = log.read_text(errors="replace")
        for match in re.finditer(r"MIKSHAT_FEATURE_LAYOUT_PROFILE\s+", text):
            try:
                record, _ = json.JSONDecoder().raw_decode(text[match.end():])
                layout_profiles.append(record)
            except ValueError:
                layout_profiles.append(None)
    profile_confirmed = (len(layout_profiles) == 1 and isinstance(layout_profiles[0], dict)
                         and str(layout_profiles[0].get("language", "")).startswith(language)
                         and layout_profiles[0].get("direction") == expected_direction
                         and layout_profiles[0].get("idiom") == ("pad" if family == "tablet" else "phone")
                         and layout_profiles[0].get("productionVerification") is True
                         and layout_profiles[0].get("runtimeProbeFlags") == [])
    locale_confirmed = (profile_confirmed if production else True) and (
        family == "tablet" or any(str(item.get("language", "")).startswith(language)
                                  and item.get("direction") == expected_direction for item in phases))
    if production:
        candidates = [item for item in phases if item.get("phase") == "verification.previewInsets.observed"]
        applied = (profile_confirmed if family == "tablet" else
                   len(candidates) == 1 and candidates[0].get("insetsLayoutMarginsFromSafeArea") is False
                   and candidates[0].get("diagnosticHookEnabled") is False
                   and candidates[0].get("runtimeProbeFlags") == [])
    elif mode == "automatic":
        applied = any(item.get("behavior") == 0 for item in candidates)
    elif mode == "fixed-title":
        applied = any(item.get("scrollEnabled") is True
                      and isinstance(item.get("heightConstraint"), (int, float)) and item["heightConstraint"] > 0
                      for item in candidates)
    else:
        applied = any(item.get("insetsLayoutMarginsFromSafeArea") is False for item in candidates)
    samples = list((directory / "native-samples").glob("sample-*.txt")) + list((directory / "native-samples").glob("lldb-*.txt"))
    frames = [path for path in samples if stack_has_frames(path.read_text(errors="replace"),
                                                        "lldb" if path.name.startswith("lldb-") else "sample")]
    monitor_path = directory / "native-samples/monitor.jsonl"
    monitor = [json.loads(line) for line in monitor_path.read_text().splitlines() if line.strip()] if monitor_path.exists() else []
    native_timeout = timed_out or any(re.search(r"exceeded execution time|test.*timed? out|test timeout", line, re.I)
                                     for line in native.get("testFailures", []))
    result = {"mode": mode, "commandExitStatus": status, "timedOut": timed_out,
              "modeApplied": applied, "phasesObserved": len(phases),
              "localeConfirmed": locale_confirmed,
              "lastPhase": phases[-1] if phases else None,
              "nativeStackCollected": bool(frames),
              "stackEvidenceFiles": [str(path.relative_to(directory)) for path in frames],
              "hangStackCollected": native_timeout and bool(frames),
              "stackReviewRequired": bool(frames),
              "debuggerFallbackAttempted": any(item.get("debuggerAttachAttempted") for item in monitor),
              "nativeExecution": native,
              "passed": status == 0 and not timed_out and applied and native["passed"]
                        and locale_confirmed,
              "scope": "Native UIKit, history and bundled-map lifecycle verification without runtime probes; no physical-device or Metal assertion"
                       if production else "UIKit-only simulator probe; no physical-device, real-feature or Metal assertion"}
    if production:
        result.update(profile=profile, language=language, family=family, layoutProfilesObserved=layout_profiles)
    if native["casesStarted"] == 0:
        result["infrastructureError"] = "No native XCTest case started"
    if production:
        rotations = [(item.get("cycle"), item.get("orientation")) for item in phases if item.get("phase") == "rotation.end"]
        probes = [item.get("phase", "") for item in phases
                  if (item.get("phase", "").startswith("probe.") and item.get("phase", "").endswith(".applied"))
                  or item.get("phase", "").startswith("layout.probe.")]
        completed = sum(item.get("phase") == "test.completed" for item in phases) == 1
        phone = family == "phone"
        result["productionEvidence"] = {"sourceInsetsObserved": applied if phone else None,
                                        "phoneSceneRotationRequired": phone,
                                        "rotationsCompleted": len(rotations),
                                        "rotationPatternMatched": rotations == ROTATIONS if phone else None,
                                        "componentProfileConfirmed": profile_confirmed,
                                        "runtimeProbePhases": probes, "testCompleted": completed if phone else None,
                                        "scope": "Actual phone scene rotation and component resizing" if phone else
                                                 "Tablet portrait/landscape component resizing; no tablet scene-rotation assertion"}
        rotation_evidence = rotations == ROTATIONS and completed if phone else not phases
        result["passed"] = result["passed"] and rotation_evidence and not probes
        result["productionLayoutSimulatorVerified"] = result["passed"]
    (directory / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def collect_diagnostics(result_bundle, directory, started):
    """Optional, capped text exports; failure never replaces the native result."""
    target = directory / "exported-diagnostics"
    target.mkdir(parents=True, exist_ok=True)
    report = {"files": [], "commands": [], "errors": [], "budgetBytes": 16 * 1024 * 1024}
    remaining = report["budgetBytes"]
    extensions = {".ips", ".hang", ".crash", ".spin", ".spindump", ".txt", ".log"}

    def copy_text(root, label, recent_app_only=False):
        nonlocal remaining
        if not root.exists():
            return
        paths = list(islice(root.rglob("*"), 512))
        paths.sort(key=lambda path: (0 if "spindump" in path.name.lower() else
                                    1 if path.suffix.lower() in {".ips", ".hang", ".crash", ".spin", ".spindump"} else 2,
                                    str(path)))
        for path in paths:
            if remaining <= 0:
                break
            try:
                if path.is_symlink() or not path.is_file() or path.suffix.lower() not in extensions:
                    continue
                if recent_app_only and (path.stat().st_mtime < started - 2
                                        or not any(name in path.name.lower() for name in ("organic", "omaps", "mikshat"))):
                    continue
                limit = min(4 * 1024 * 1024, remaining)
                with path.open("rb") as stream:
                    data = stream.read(limit)
                if b"\x00" in data:
                    continue
                source_size = path.stat().st_size
                # A byte cap may split the final Arabic character. Keep every
                # complete character while still rejecting binary/invalid text.
                data = codecs.getincrementaldecoder("utf-8")().decode(data, final=source_size <= len(data)).encode("utf-8")
                relative = Path(label) / path.relative_to(root)
                destination = target / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
                remaining -= len(data)
                report["files"].append({"file": str(relative), "bytes": len(data),
                                         "sourceBytes": source_size, "truncated": source_size > len(data)})
            except (OSError, UnicodeDecodeError) as error:
                report["errors"].append(str(error))

    def optional(args, timeout):
        entry = {"command": args}
        try:
            result = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
            entry.update(exitStatus=result.returncode, stdout=captured_text(result.stdout), stderr=captured_text(result.stderr))
        except subprocess.TimeoutExpired as error:
            entry.update(timedOut=True, stdout=captured_text(error.output), stderr=captured_text(error.stderr), error=str(error))
        except OSError as error:
            entry["error"] = str(error)
        report["commands"].append(entry)
        return entry

    try:
        if result_bundle.exists():
            for kind in ("attachments", "diagnostics"):
                help_result = optional(["xcrun", "xcresulttool", "help", "export", kind], 10)
                help_text = help_result.get("stdout", "") + help_result.get("stderr", "")
                supported = (help_result.get("exitStatus") == 0 and "--path" in help_text and "--output-path" in help_text
                             and (kind != "attachments" or "--only-failures" in help_text))
                if supported:
                    with tempfile.TemporaryDirectory(prefix="mikshat-xcresult-" + kind + "-") as temp:
                        exported = Path(temp) / "export"
                        export = ["xcrun", "xcresulttool", "export", kind, "--path", str(result_bundle),
                                  "--output-path", str(exported)]
                        if kind == "attachments":
                            export.append("--only-failures")
                        optional(export, 60)
                        copy_text(exported, "xcresult-" + kind)
                else:
                    report["errors"].append("Installed xcresulttool did not advertise the expected " + kind + " export command")
        copy_text(Path.home() / "Library/Logs/DiagnosticReports", "host-app-reports", True)
    except (OSError, ValueError) as error:
        report["errors"].append(str(error))
    (target / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--production", action="store_true", help="Verify production features and layout on Arabic/English phones/tablets without runtime probes")
    args = parser.parse_args()
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    # Compiled objects and xcresult bundles stay outside the compact artifact.
    derived = ROOT / "build/RotationDiagnosticDerivedData"
    results = []
    simulators = []
    runs = [dict(profile, mode="automatic") for profile in PRODUCTION_PROFILES] if args.production else [
        dict(id=mode, mode=mode, family="phone", language="ar", region="SA") for mode in MODES]
    summary = {"productionFixVerified": False, "passes": results,
               "productionLayoutSimulatorVerified": False,
               "scope": "Arabic/English phone scene rotation, phone/tablet component resizing, history and bundled-map lifecycle; no tablet scene-rotation, physical-device or Metal assertion"
                        if args.production else "Three UIKit-only layout probes on isolated iPhone simulators; no upload"}
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
        device_types = json.loads(output(["xcrun", "simctl", "list", "--json", "devicetypes"]))["devicetypes"]
        for run in runs:
            run["deviceType"] = device_type(run["family"], device_types)
            udid = output(["xcrun", "simctl", "create", "Mikshat verification " + run["id"],
                           run["deviceType"], runtime])
            simulators.append(udid)
        (destination / "simulator-profiles.json").write_text(json.dumps([
            dict(run, udid=udid, runtime=runtime) for run, udid in zip(runs, simulators)], indent=2) + "\n")
        if args.production:
            summary["requiredProfiles"] = [run["id"] for run in runs]
            summary["requiredCasesPerProfile"] = {
                run["id"]: sum(len(methods) for methods in selected_cases(True, run["family"]).values()) for run in runs}
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
            if path.name.startswith("MikshatTitleInsets-"):
                continue
            try:
                plan = plistlib.loads(path.read_bytes())
                patch_plan(plan, "automatic", args.production)
                plans.append((path, plan))
            except ValueError:
                continue
        if len(plans) != 1:
            raise RuntimeError("Expected exactly one compiled native OMapsTests plan")
        apps = [app for app in (products / "Debug-iphonesimulator").glob("*.app")
                if plistlib.loads((app / "Info.plist").read_bytes()).get("CFBundleIdentifier") == BUNDLE]
        if len(apps) != 1:
            raise RuntimeError("Expected exactly one compiled Debug app host")
        for index, (run, udid) in enumerate(zip(runs, simulators)):
            mode = run["mode"]
            directory = destination / run["id"]
            directory.mkdir()
            print("Running native verification profile " + run["id"], flush=True)
            if index != 0:
                command(["xcrun", "simctl", "boot", udid])
                command(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=180)
            command(["xcrun", "simctl", "install", udid, str(apps[0])])
            command(["xcrun", "simctl", "privacy", udid, "grant", "location", BUNDLE])
            command(["xcrun", "simctl", "location", udid, "set", "26.2317333333,44.9453"])
            plan_path = products / ("MikshatTitleInsets-" + run["id"] + ".xctestrun")
            plan_path.write_bytes(plistlib.dumps(patch_plan(plans[0][1], mode, args.production)))
            sampler = PhaseSampler(udid, directory / "native-samples")
            result_bundle = ROOT / "build" / ("RotationDiagnostic-" + run["id"] + ".xcresult")
            test = ["xcodebuild", "test-without-building", "-xctestrun", str(plan_path),
                    "-destination", "id=" + udid, "-destination-timeout", "60",
                    "-resultBundlePath", str(result_bundle),
                    "-parallel-testing-enabled", "NO", "-test-timeouts-enabled", "YES",
                    "-testLanguage", run["language"], "-testRegion", run["region"],
                    "-default-test-execution-time-allowance", "60", "-maximum-test-execution-time-allowance", "60",
                    *testing_filters(args.production, run["family"]),
                    "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO"]
            status, timed_out = run_bounded(test, directory / "xcodebuild-test.log", sampler,
                                           600 if args.production else 180)
            collect_diagnostics(result_bundle, directory, sampler.started)
            results.append(evaluate_mode(mode, directory, status, timed_out, args.production,
                                         language=run["language"], profile=run["id"] if args.production else None,
                                         family=run["family"]))
            command(["xcrun", "simctl", "shutdown", udid])
        summary["classification"] = classify(results, args.production)
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
        summary["passedProbeModes"] = [item["mode"] for item in results if item["mode"] != "automatic" and item["passed"]]
        summary["allNativeCasesPassed"] = len(results) == len(runs) and all(item["passed"] for item in results)
        summary["productionLayoutSimulatorVerified"] = (args.production and summary["allNativeCasesPassed"]
                                                       and summary.get("classification") == "productionLayoutSimulatorPassed")
        (destination / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        archive = destination / "rotation-diagnostics.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
            for path in destination.rglob("*"):
                if path.is_file() and path != archive:
                    package.write(path, str(path.relative_to(destination)))
        print(json.dumps(summary), flush=True)
    if not summary["allNativeCasesPassed"] or (args.production and not summary["productionLayoutSimulatorVerified"]):
        raise SystemExit("The rotation verification did not establish all required native cases; inspect the classification and native stacks")


if __name__ == "__main__":
    main()
