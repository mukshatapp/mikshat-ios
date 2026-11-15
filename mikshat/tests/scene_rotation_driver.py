"""Drive physical iPad rotation in the isolated CI simulator via public devicectl.

Hosted UIKit tests cannot request a different interface orientation in a multitasking
iPad app. They exchange versioned requests here; the tests still verify the actual
scene orientation and window/map bounds after each physical device command.
"""
import argparse
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
        result = subprocess.run(command, text=True, capture_output=True, timeout=25)
        record = {"command": command, "returncode": result.returncode,
                  "stdout": result.stdout, "stderr": result.stderr}
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

    try:
        # Fail before announcing readiness if the public device service is not available.
        device_command("get", "prewarm")
        documents = resolve_documents()
        ready = publish_ready(documents)
        atomic_json(options.ready_output, dict(ready, documents=str(documents)))
        event("MIKSHAT_SCENE_DRIVER_READY", dict(ready, documents=str(documents)))
        handled = set()
        resolved_at = heartbeat_at = time.monotonic()
        container_unavailable_at = None
        while not stopping:
            now = time.monotonic()
            if now - resolved_at >= 2:
                # test-without-building may reinstall the host. Follow its real container
                # rather than publishing a stale marker into an old sandbox.
                try:
                    current_documents = resolve_documents()
                except RuntimeError as error:
                    if container_unavailable_at is None:
                        container_unavailable_at = now
                    event("MIKSHAT_SCENE_DRIVER_RESOLUTION_RETRY",
                          {"error": str(error), "elapsedSeconds": now - container_unavailable_at,
                           "documents": str(documents)})
                    if now - container_unavailable_at > 30:
                        raise
                    if documents.is_dir():
                        publish_ready(documents)
                    time.sleep(0.2)
                    continue
                container_unavailable_at = None
                if current_documents != documents:
                    old_marker = documents / (PREFIX + "ready.json")
                    if (read_json(old_marker) or {}).get("session") == session:
                        old_marker.unlink(missing_ok=True)
                    documents = current_documents
                    ready = publish_ready(documents)
                    atomic_json(options.ready_output, dict(ready, documents=str(documents)))
                    event("MIKSHAT_SCENE_DRIVER_CONTAINER", dict(ready, documents=str(documents)))
                resolved_at = now
            if now - heartbeat_at >= 1:
                publish_ready(documents)
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
        if documents is not None:
            marker = documents / (PREFIX + "ready.json")
            if (read_json(marker) or {}).get("session") == session:
                marker.unlink(missing_ok=True)
        options.ready_output.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
