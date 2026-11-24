#!/usr/bin/env python3
"""Check the selected Xcode's Metal compiler before native tests and archiving."""

import argparse
import json
from pathlib import Path
import shlex
import subprocess
import time


PLATFORMS = {"iphonesimulator": "air64-apple-ios15.0-simulator", "iphoneos": "air64-apple-ios15.0"}
OUTPUT_LIMIT = 256 * 1024


def output_text(value):
    if isinstance(value, bytes):
        value = value.decode(errors="replace")
    return str(value or "")[:OUTPUT_LIMIT]


def run(args, report, log, timeout=30):
    entry = {"command": args, "timeoutSeconds": timeout, "timedOut": False}
    print("$ " + shlex.join(args), flush=True)
    try:
        result = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
        entry.update(exitStatus=result.returncode, stdout=output_text(result.stdout), stderr=output_text(result.stderr))
    except subprocess.TimeoutExpired as error:
        entry.update(exitStatus=None, timedOut=True, stdout=output_text(error.output),
                     stderr=output_text(error.stderr), error=str(error))
    except OSError as error:
        entry.update(exitStatus=None, stdout="", stderr="", error=str(error))
    report["commands"].append(entry)
    with log.open("a") as stream:
        stream.write("\n$ " + shlex.join(args) + "\n" + json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
    print("exit=" + str(entry["exitStatus"]) + " timedOut=" + str(entry["timedOut"]), flush=True)
    if entry["exitStatus"] != 0:
        print((entry["stderr"] or entry["stdout"] or entry.get("error", ""))[-4000:], flush=True)
    return entry


def functional_check(directory, report, log, attempt, stage="initial"):
    source = directory / "probe.metal"
    source.write_text("#include <metal_stdlib>\nusing namespace metal;\n"
                      "kernel void probe(device uint *out [[buffer(0)]], uint i [[thread_position_in_grid]]) { out[i] = i; }\n")
    platforms = {}
    for platform, target in PLATFORMS.items():
        air, library = directory / (platform + ".air"), directory / (platform + ".metallib")
        air.unlink(missing_ok=True)
        library.unlink(missing_ok=True)
        sdk = run(["xcrun", "--sdk", platform, "--show-sdk-path"], report, log)
        if sdk["exitStatus"] != 0 or not sdk["stdout"].strip():
            platforms[platform] = False
            continue
        compile_result = run(["xcrun", "--sdk", platform, "metal", "-c", "-target", target,
                              "-isysroot", sdk["stdout"].strip(), str(source), "-o", str(air)], report, log)
        linked = False
        if compile_result["exitStatus"] == 0 and air.is_file() and air.stat().st_size > 0:
            link_result = run(["xcrun", "--sdk", platform, "metal", "-target", target,
                               "-o", str(library), str(air)], report, log)
            linked = link_result["exitStatus"] == 0 and library.is_file() and library.stat().st_size > 0
        platforms[platform] = linked
    passed = all(platforms.values())
    report["functionalChecks"].append({"stage": stage, "afterDownloadAttempt": attempt, "platforms": platforms, "passed": passed})
    return passed


def prepare(directory):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / "preflight.log"
    log.write_text("Selected-Xcode Metal compile and link preflight; no alternative compiler is injected.\n")
    report = {"passed": False, "commands": [], "functionalChecks": [], "downloadAttempts": 0,
              "scope": "Selected Xcode 27.0; real simulator and device Metal compile plus link"}
    try:
        version = run(["xcodebuild", "-version"], report, log)
        report["selectedXcode"] = version["stdout"].strip()
        if version["exitStatus"] != 0 or "Xcode 27.0" not in version["stdout"].splitlines():
            raise RuntimeError("The selected Xcode must be 27.0")
        run(["xcrun", "-k"], report, log)
        # Listing runtimes lets CoreSimulator settle its pending mounts. Avoid
        # contacting the component catalog on an already functional image.
        run(["xcrun", "simctl", "runtime", "list"], report, log, timeout=60)
        run(["xcrun", "-k"], report, log)
        report["passed"] = functional_check(directory, report, log, 0)
        if not report["passed"]:
            run(["xcodebuild", "-runFirstLaunch", "-checkForNewerComponents"], report, log, timeout=120)
            run(["xcrun", "simctl", "runtime", "list"], report, log, timeout=60)
            run(["xcrun", "-k"], report, log)
            report["passed"] = functional_check(directory, report, log, 0, "afterFirstLaunch")
        if not report["passed"]:
            run(["xcodebuild", "-showComponent", "MetalToolchain"], report, log, timeout=60)
            run(["xcrun", "--find", "metal"], report, log)
            for attempt in range(1, 4):
                report["downloadAttempts"] = attempt
                run(["xcodebuild", "-downloadComponent", "MetalToolchain"], report, log, timeout=120)
                run(["xcrun", "simctl", "runtime", "list"], report, log, timeout=60)
                run(["xcrun", "-k"], report, log)
                # A failed download may still have installed/mounted a working
                # component. Conversely, download exit zero is not proof of one.
                report["passed"] = functional_check(directory, report, log, attempt, "afterDownload")
                if report["passed"]:
                    break
                if attempt < 3:
                    time.sleep((5, 15)[attempt - 1])
        if not report["passed"]:
            report["error"] = "Selected Xcode's Metal compiler could not compile and link for both iOS SDKs"
    except (OSError, RuntimeError) as error:
        report["error"] = str(error)
    finally:
        (directory / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, nargs="?", default=Path("build/metal-preflight"))
    args = parser.parse_args()
    report = prepare(args.output)
    print(json.dumps({"passed": report["passed"], "downloadAttempts": report["downloadAttempts"],
                      "error": report.get("error"), "log": str(args.output / "preflight.log")}))
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
