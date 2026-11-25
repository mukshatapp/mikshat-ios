#!/usr/bin/env python3
"""Require both Go To entries and rotation on a fresh active-Metal simulator."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import renderer


def command(arguments, timeout=60, **kwargs):
    return subprocess.run(arguments, check=True, text=True, timeout=timeout, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    options = parser.parse_args()
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    runtimes = json.loads(renderer.simctl("list", "--json", "runtimes").stdout)["runtimes"]
    matching = [runtime for runtime in runtimes if runtime.get("isAvailable")
                and runtime.get("version") == "27.0" and "iOS" in runtime.get("identifier", "")]
    if len(matching) != 1:
        raise RuntimeError("Exactly iOS 27.0 is required for the vehicle routing gate")
    udid = renderer.simctl("create", "Mikshat vehicle route verification",
                          "com.apple.CoreSimulator.SimDeviceType.iPhone-16", matching[0]["identifier"]).stdout.strip()
    (output / "simulator.json").write_text(json.dumps({"udid": udid, "runtime": matching[0]}, indent=2) + "\n")
    monitors = []
    streams = []
    try:
        renderer.simctl("boot", udid)
        command(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=180)
        renderer.prepare(SimpleNamespace(products=options.products, output_dir=output, udid=udid, map_file=None))
        for name, script, arguments in (
            ("capture", "renderer.py", ["capture", "--udid", udid, "--output-dir", str(output / "screenshots")]),
            ("stack-monitor", "hang_sampler.py", ["--udid", udid, "--output-dir", str(output / "native-stacks"),
                                                  "--max-seconds", "480"]),
        ):
            stream = (output / (name + ".log")).open("w")
            streams.append(stream)
            monitors.append(subprocess.Popen([sys.executable, "-u", str(Path(__file__).with_name(script)), *arguments],
                                             stdout=stream, stderr=subprocess.STDOUT))
        plan = options.products.resolve() / "MikshatRendererRotationArabic.xctestrun"
        filters = [f"-only-testing:OMapsTests/{name}/{method}"
                   for name, methods in renderer.CASES.items() for method in methods]
        result = output / "VehicleRouting.xcresult"
        with (output / "xcodebuild-renderer.log").open("w") as log:
            try:
                status = subprocess.run([
                    "xcodebuild", "test-without-building", "-xctestrun", str(plan),
                    "-destination", "id=" + udid, "-destination-timeout", "120",
                    "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                    "-maximum-concurrent-test-simulator-destinations", "1",
                    "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120",
                    "-maximum-test-execution-time-allowance", "180", *filters,
                    "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO",
                ], text=True, stdout=log, stderr=subprocess.STDOUT, timeout=480).returncode
            except subprocess.TimeoutExpired:
                status = -1
                log.write("\nVehicle routing exceeded its bounded 480-second timeout.\n")
        for monitor in monitors:
            monitor.terminate()
        for monitor in monitors:
            try:
                monitor.wait(timeout=20)
            except subprocess.TimeoutExpired:
                monitor.kill()
                monitor.wait(timeout=10)
        renderer.verify(SimpleNamespace(output_dir=output, udid=udid,
                                        test_outcome="success" if status == 0 else "failure"))
    finally:
        for monitor in monitors:
            if monitor.poll() is None:
                monitor.kill()
                monitor.wait(timeout=10)
        for stream in streams:
            stream.close()
        for operation in ("shutdown", "delete"):
            try:
                renderer.simctl(operation, udid, check=False)
            except subprocess.TimeoutExpired as error:
                print(f"Simulator cleanup failed: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()
