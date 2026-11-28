#!/usr/bin/env python3
"""Reuse the input timestamp manifest written by the responsive iOS workflow."""

import hashlib
import json
import os
from pathlib import Path
import sys


MANIFEST = Path("build/SearchDerivedData/mikshat-input-mtimes.json")


def inputs():
    for root in ("iphone", "libs", "xcode", "data", "3party", "private"):
        if not Path(root).is_dir():
            continue
        for directory, children, files in os.walk(root):
            children[:] = [name for name in children if name not in (".git", "__pycache__", "node_modules")]
            yield Path(directory)
            for name in files:
                if name != ".git":
                    yield Path(directory) / name


def digest(path):
    if path.is_dir():
        names = sorted(child.name for child in path.iterdir() if child.name != ".git")
        return hashlib.sha256("\n".join(names).encode()).hexdigest()
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("restore", "record"):
        raise SystemExit("Usage: cache_inputs.py restore|record")
    if sys.argv[1] == "restore":
        restored = 0
        if MANIFEST.exists():
            for item in json.loads(MANIFEST.read_text()):
                path = Path(item["path"])
                if path.exists() and not path.is_symlink() and digest(path) == item["sha256"]:
                    os.utime(path, ns=(path.stat().st_atime_ns, item["mtime_ns"]))
                    restored += 1
        print(f"Restored timestamps for {restored} unchanged build inputs")
    else:
        entries = []
        for path in inputs():
            if path.exists() and not path.is_symlink():
                entries.append(dict(path=str(path), sha256=digest(path), mtime_ns=path.stat().st_mtime_ns))
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(json.dumps(entries))
        print(f"Recorded {len(entries)} build input timestamps")


if __name__ == "__main__":
    main()
