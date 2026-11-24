#!/usr/bin/env python3
"""Collect a native stack from the exact simulator app when its layout phase stops advancing."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import time
import uuid


BUNDLE = "com.mikshat.maps.debug"
JOURNAL = "mikshat-rotation-phases.jsonl"
TEXT_LIMIT = 1024 * 1024


def captured_text(value):
    if isinstance(value, bytes):
        value = value.decode(errors="replace")
    return str(value or "")[:TEXT_LIMIT]


def stack_has_frames(text, kind):
    if kind == "lldb":
        return bool(re.search(r"(?m)^\s*\*?\s*thread #\d+", text)
                    and re.search(r"(?m)^\s*\*?\s*frame #\d+:\s+0x[0-9a-fA-F]+", text))
    return bool("Call graph:" in text and re.search(r"\bThread[_ ]\d+", text)
                and re.search(r"(?m)^\s*[+!:| ]+\d+\s+\S.*(?:\(in [^)\n]+\)|\[0x[0-9a-fA-F]+\])", text))


def valid_identity(record):
    try:
        return (record.get("version") == 1 and record.get("bundle") == BUNDLE
                and type(record.get("pid")) is int and record["pid"] > 1
                and type(record.get("sequence")) is int and record["sequence"] > 0
                and str(uuid.UUID(record["run"])) == record["run"].lower())
    except (KeyError, ValueError, TypeError, AttributeError):
        return False


def phase_candidate(record, now, threshold):
    """A stale journal is a sampling candidate, not proof that the app is hung."""
    return (valid_identity(record)
            and record.get("mainThread") is True
            and type(record.get("pid")) is int and record["pid"] > 1
            and isinstance(record.get("run"), str) and bool(record["run"])
            and type(record.get("sequence")) is int and record["sequence"] > 0
            and isinstance(record.get("timestamp"), (int, float))
            and now - record["timestamp"] >= threshold
            # UIKit may enter automatic layout after our synchronous call has
            # returned. A stale .end marker must remain eligible for a native
            # stack; only the explicit test terminal disables sampling.
            and record.get("phase") != "test.completed")


def phase_records(data, started):
    """Ignore incomplete writes and records from an earlier app invocation."""
    records = []
    for line in data.splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if (valid_identity(record) and isinstance(record.get("timestamp"), (int, float))
                and record["timestamp"] >= started - 2):
            records.append(record)
    return records


def exact_app_process(command, executable):
    # ps may append launch arguments; a substring match could sample a shell or
    # another simulator. The executable must occupy the command's exact prefix.
    value = command.strip()
    expected = str(executable)
    return value == expected or value.startswith(expected + " ")


class PhaseSampler:
    def __init__(self, udid, output, threshold=10):
        self.udid = udid
        self.output = Path(output).resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.threshold = threshold
        self.started = time.time()
        self.journal = None
        self.executable = None
        self.seen = set()
        self.sampled = set()
        self.fallback_pids = set()
        self.last_discovery = 0

    def log(self, name, value):
        with (self.output / name).open("a") as stream:
            stream.write(json.dumps(value, ensure_ascii=False) + "\n")

    def discover(self):
        if time.monotonic() - self.last_discovery < 5:
            return
        self.last_discovery = time.monotonic()
        try:
            def container(kind):
                result = subprocess.run(["xcrun", "simctl", "get_app_container", self.udid, BUNDLE, kind],
                                        text=True, capture_output=True, timeout=10)
                return Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else None
            app, data = container("app"), container("data")
            if app and data:
                info = plistlib.loads((app / "Info.plist").read_bytes())
                executable = info.get("CFBundleExecutable")
                if info.get("CFBundleIdentifier") != BUNDLE or not executable:
                    raise ValueError("The installed host is not the expected Mikshat Debug app")
                self.executable = app / executable
                self.journal = data / "Documents" / JOURNAL
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            self.log("monitor.jsonl", {"event": "discovery-error", "timestamp": time.time(), "error": str(error)})

    def tick(self):
        if self.journal is None or not self.journal.exists():
            self.discover()
        if self.journal is None or not self.journal.exists():
            return
        try:
            # Keep both the full per-invocation journal and the phases seen by
            # this external monitor. Fresh-host repetitions replace the source.
            data = self.journal.read_text()
            records = phase_records(data, self.started)
            for record in records:
                identity = (record.get("run"), record.get("sequence"))
                if identity not in self.seen:
                    self.seen.add(identity)
                    self.log("phases-seen.jsonl", record)
            if not records:
                return
            last = records[-1]
            (self.output / ("phases-" + str(last["run"]) + ".jsonl")).write_text(data)
            identity = (last.get("run"), last.get("sequence"))
            if len(self.sampled) >= 6 or identity in self.sampled:
                return
            if not phase_candidate(last, time.time(), self.threshold):
                return
            self.sampled.add(identity)
            self.sample(last)
        except (OSError, ValueError, TypeError) as error:
            self.log("monitor.jsonl", {"event": "journal-error", "timestamp": time.time(), "error": str(error)})

    def process_matches(self, pid):
        ps = subprocess.run(["ps", "-p", str(pid), "-o", "command="],
                            text=True, capture_output=True, timeout=5)
        return (ps.returncode == 0 and self.executable is not None
                and exact_app_process(ps.stdout, self.executable)), ps.stdout.strip()

    def capture_tool(self, command, stem, timeout):
        started = time.monotonic()
        report = {"command": command, "timedOut": False}
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
            stdout, stderr = captured_text(result.stdout), captured_text(result.stderr)
            report["exitStatus"] = result.returncode
        except subprocess.TimeoutExpired as error:
            stdout, stderr = captured_text(error.output), captured_text(error.stderr)
            report.update(timedOut=True, exitStatus=None, error=str(error))
        except OSError as error:
            stdout, stderr = "", ""
            report.update(exitStatus=None, error=str(error))
        (self.output / (stem + ".stdout.txt")).write_text(stdout)
        (self.output / (stem + ".stderr.txt")).write_text(stderr)
        report.update(elapsedSeconds=time.monotonic() - started, stdout=stdout[-8000:], stderr=stderr[-8000:])
        return report, stdout + stderr

    def fallback(self, phase):
        pid = phase["pid"]
        report = {"event": "stale-phase-lldb", "timestamp": time.time(), "phase": phase}
        if pid in self.fallback_pids:
            return
        try:
            # The app may have resumed or XCTest may have relaunched it during
            # sampling. Never attach to an unverified or newly reused process.
            records = phase_records(self.journal.read_text(), self.started) if self.journal else []
            last = records[-1] if records else {}
            same_phase = all(last.get(key) == phase.get(key) for key in ("run", "sequence", "pid"))
            matched, process = self.process_matches(pid)
            report["processCommand"] = process
            if not same_phase or not phase_candidate(last, time.time(), self.threshold) or not matched:
                report["result"] = "fallback-identity-or-phase-changed"
            else:
                self.fallback_pids.add(pid)
                stem = "capture-lldb-" + phase["run"] + "-" + str(phase["sequence"])
                command = ["xcrun", "lldb", "--batch", "-p", str(pid),
                           "-o", "thread backtrace -c 100 all", "-o", "process detach", "-o", "quit"]
                capture, text = self.capture_tool(command, stem, 15)
                path = self.output / ("lldb-" + phase["run"] + "-" + str(phase["sequence"]) + ".txt")
                path.write_text(text)
                frames = stack_has_frames(text, "lldb")
                report.update(capture, result="lldb-stack" if frames else "lldb-no-stack", file=str(path),
                              stackFramesCaptured=frames, debuggerAttachAttempted=True)
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            report.update(result="fallback-error", error=str(error))
        self.log("monitor.jsonl", report)

    def sample(self, phase):
        pid = phase["pid"]
        report = {"event": "stale-phase-sample", "timestamp": time.time(), "phase": phase,
                  "scope": "Native process stack candidate; staleness alone does not prove a hang"}
        fallback = False
        try:
            matched, process = self.process_matches(pid)
            report["processCommand"] = process
            if not matched:
                report["result"] = "process-not-matched"
            else:
                suffix = phase["run"] + "-" + str(phase["sequence"])
                path = self.output / ("sample-" + suffix + ".txt")
                capture, _ = self.capture_tool(["/usr/bin/sample", str(pid), "3", "-file", str(path)],
                                               "capture-sample-" + suffix, 20)
                text = path.read_text(errors="replace") if path.is_file() else ""
                frames = stack_has_frames(text, "sample")
                report.update(capture, result="sampled" if frames else "sample-no-stack", file=str(path),
                              partialFilePresent=path.is_file(), stackFramesCaptured=frames)
                fallback = not frames
        except (OSError, subprocess.TimeoutExpired) as error:
            report.update(result="sample-error", error=str(error))
        self.log("monitor.jsonl", report)
        print("MIKSHAT_STALE_PHASE_SAMPLE " + json.dumps(report), flush=True)
        if fallback:
            self.fallback(phase)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--threshold", type=float, default=10)
    parser.add_argument("--max-seconds", type=float, default=600)
    options = parser.parse_args()
    stopping = False
    def stop(_signal, _frame):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sampler = PhaseSampler(options.udid, options.output_dir, options.threshold)
    deadline = time.monotonic() + options.max_seconds
    try:
        while not stopping and time.monotonic() < deadline:
            sampler.tick()
            time.sleep(0.5)
    finally:
        sampler.tick()


if __name__ == "__main__":
    main()
