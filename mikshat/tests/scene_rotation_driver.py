"""Drive physical iPad rotation in the isolated CI simulator via public devicectl.

Hosted UIKit tests cannot request a different interface orientation in a multitasking
iPad app. They exchange versioned requests here; the tests still verify the actual
scene orientation and window/map bounds after each physical device command.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import uuid


VERSION = 1
PREFIX = "mikshat-scene-rotation-"
ORIENTATIONS = {"portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight"}


def atomic_json(path, payload):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(payload, sort_keys=True) + "\n")
    os.replace(temporary, path)


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--bundle", required=True)
    parser.add_argument("--ready-output", type=Path, required=True)
    options = parser.parse_args()
    options.ready_output.parent.mkdir(parents=True, exist_ok=True)
    options.ready_output.unlink(missing_ok=True)
    artifacts = options.ready_output.parent / "scene-rotation"
    artifacts.mkdir(parents=True, exist_ok=True)
    session = str(uuid.uuid4())
    stopping = False
    documents = None
    discovery = None
    lookup = None

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def event(name, payload):
        print(name + " " + json.dumps(payload, sort_keys=True), flush=True)

    def device_command(operation, name, orientation=None):
        command = ["xcrun", "devicectl", "device", "orientation", operation,
                   "--device", options.udid]
        if orientation is not None:
            command.append(orientation)
        command += ["--timeout", "20", "--json-output", str(artifacts / (name + ".json"))]
        started_at = time.time()
        started_monotonic = time.monotonic()
        event("MIKSHAT_SCENE_DRIVER_COMMAND_START", {"command": command, "startedAt": started_at})
        try:
            result = subprocess.run(command, text=True, capture_output=True, timeout=25)
        except subprocess.TimeoutExpired as error:
            # TimeoutExpired may carry bytes even with text=True. Preserve any
            # partial public-command output before returning the strict failure ACK.
            stdout, stderr = error.stdout or "", error.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", errors="replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
            record = {"command": command, "returncode": None, "timedOut": True,
                      "stdout": stdout, "stderr": stderr, "startedAt": started_at,
                      "completedAt": time.time(), "durationSeconds": time.monotonic() - started_monotonic}
            atomic_json(artifacts / (name + "-command.json"), record)
            event("MIKSHAT_SCENE_DRIVER_COMMAND", record)
            raise RuntimeError("Public devicectl orientation command timed out after 25 seconds") from error
        record = {"command": command, "returncode": result.returncode,
                  "stdout": result.stdout, "stderr": result.stderr, "startedAt": started_at,
                  "completedAt": time.time(), "durationSeconds": time.monotonic() - started_monotonic}
        atomic_json(artifacts / (name + "-command.json"), record)
        event("MIKSHAT_SCENE_DRIVER_COMMAND", record)
        if result.returncode:
            raise RuntimeError("Public devicectl command failed: " + result.stderr)
        if not isinstance(read_json(artifacts / (name + ".json")), dict):
            raise RuntimeError("Public devicectl command did not produce its required JSON result")

    def resolve_documents():
        try:
            result = subprocess.run(["xcrun", "simctl", "get_app_container", options.udid, options.bundle, "data"],
                                    text=True, capture_output=True, timeout=10)
        except subprocess.TimeoutExpired as error:
            raise RuntimeError("Public simctl get_app_container timed out after 10 seconds") from error
        if result.returncode:
            raise RuntimeError("Cannot resolve installed test host container: " + result.stderr)
        directory = Path(result.stdout.strip()) / "Documents"
        directory.mkdir(parents=True, exist_ok=True)
        return directory

    def publish_ready(directory):
        ready = {"version": VERSION, "session": session, "driver": "devicectl",
                 "heartbeatAt": time.time(), "udid": options.udid}
        atomic_json(directory / (PREFIX + "ready.json"), ready)
        return ready

    def discover_documents():
        started_at, started_monotonic = time.time(), time.monotonic()
        directory = None
        record = {"startedAt": started_at}
        try:
            directory = resolve_documents()
            record.update(success=True, documents=str(directory))
        except Exception as error:
            record.update(success=False, error=str(error))
        record.update(completedAt=time.time(), durationSeconds=time.monotonic() - started_monotonic)
        return directory, record

    try:
        # Fail before announcing readiness if the public device service is not available.
        device_command("get", "prewarm")
        documents = resolve_documents()
        ready = publish_ready(documents)
        atomic_json(options.ready_output, dict(ready, documents=str(documents)))
        event("MIKSHAT_SCENE_DRIVER_READY", dict(ready, documents=str(documents)))
        handled = set()
        heartbeat_at = time.monotonic()
        next_lookup_at = heartbeat_at + 2
        documents_missing_at = None
        discovery = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mikshat-container-lookup")
        while not stopping:
            now = time.monotonic()
            if lookup is not None and lookup.done():
                # Only the main thread applies a completed public-container lookup.
                # A slow auxiliary RPC must not starve requests in the known sandbox.
                current_documents, record = lookup.result()
                lookup = None
                next_lookup_at = now + 2
                event("MIKSHAT_SCENE_DRIVER_LOOKUP", record)
                if current_documents is not None and current_documents != documents:
                    old_marker = documents / (PREFIX + "ready.json")
                    if (read_json(old_marker) or {}).get("session") == session:
                        old_marker.unlink(missing_ok=True)
                    documents = current_documents
                    heartbeat_at = 0
                    event("MIKSHAT_SCENE_DRIVER_CONTAINER", {"documents": str(documents), "session": session})
            if lookup is None and now >= next_lookup_at:
                event("MIKSHAT_SCENE_DRIVER_LOOKUP_START", {"startedAt": time.time()})
                lookup = discovery.submit(discover_documents)
            if not documents.is_dir():
                if documents_missing_at is None:
                    documents_missing_at = now
                    event("MIKSHAT_SCENE_DRIVER_DOCUMENTS_MISSING", {"documents": str(documents), "startedAt": time.time()})
                if now - documents_missing_at >= 30:
                    raise RuntimeError("The installed test host Documents directory remained unavailable for 30 seconds")
                time.sleep(0.1)
                continue
            documents_missing_at = None
            if now - heartbeat_at >= 1:
                try:
                    ready = publish_ready(documents)
                except FileNotFoundError:
                    # A reinstall may remove this directory between is_dir and write.
                    continue
                atomic_json(options.ready_output, dict(ready, documents=str(documents)))
                heartbeat_at = now
            request = read_json(documents / (PREFIX + "request.json"))
            if request and request.get("session") == session and request.get("id") not in handled:
                identifier = request.get("id", "")
                response = {"version": VERSION, "session": session, "id": identifier,
                            "success": False, "physicalOrientation": request.get("physicalOrientation")}
                try:
                    uuid.UUID(identifier)
                    if request.get("version") != VERSION or request.get("physicalOrientation") not in ORIENTATIONS:
                        raise ValueError("Unsupported physical rotation request")
                    device_command("set", "rotation-" + identifier, request["physicalOrientation"])
                    response["success"] = True
                except Exception as error:
                    response["error"] = str(error)
                response["completedAt"] = time.time()
                atomic_json(documents / (PREFIX + "response.json"), response)
                handled.add(identifier)
                event("MIKSHAT_SCENE_DRIVER_RESPONSE", response)
                if not response["success"]:
                    raise RuntimeError(response["error"])
            time.sleep(0.1)
    finally:
        if lookup is not None:
            lookup.cancel()
        if discovery is not None:
            # At most one public lookup is running, with its own 10-second
            # subprocess bound. Wait for it so no worker/child survives shutdown.
            discovery.shutdown(wait=True, cancel_futures=True)
        if documents is not None:
            marker = documents / (PREFIX + "ready.json")
            if (read_json(marker) or {}).get("session") == session:
                marker.unlink(missing_ok=True)
        options.ready_output.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
