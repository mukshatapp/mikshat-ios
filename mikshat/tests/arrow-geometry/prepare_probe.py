#!/usr/bin/env python3
"""Extract the production indicator verbatim; assemble a standalone UIKit app."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil


CLASS = "MikshatDirectionIndicator"
INTERFACE = pathlib.Path("iphone/Maps/UI/Mikshat/MikshatInterface.swift")
MATH = pathlib.Path("iphone/Maps/UI/Mikshat/MikshatNavigationMath.swift")


def extract_class(source):
    # Mask comments and Swift strings before counting braces. Keep byte offsets
    # unchanged, then slice the original source, never a rewritten class body.
    masked = list(source)
    i, comment_depth = 0, 0
    while i < len(source):
        start = i
        if source.startswith("//", i):
            end = source.find("\n", i)
            i = len(source) if end < 0 else end
        elif source.startswith("/*", i):
            i += 2
            comment_depth = 1
            while i < len(source) and comment_depth:
                if source.startswith("/*", i):
                    comment_depth += 1
                    i += 2
                elif source.startswith("*/", i):
                    comment_depth -= 1
                    i += 2
                else:
                    i += 1
            if comment_depth:
                raise ValueError("Unterminated Swift block comment")
        else:
            match = re.match(r'(#+)?("""|")', source[i:])
            if not match:
                i += 1
                continue
            hashes, quote = match.group(1) or "", match.group(2)
            i += len(match.group(0))
            terminator = quote + hashes
            while i < len(source):
                if source.startswith(terminator, i):
                    i += len(terminator)
                    break
                if source.startswith("\\" + hashes, i):
                    i += len(hashes) + 2
                else:
                    i += 1
            else:
                raise ValueError("Unterminated Swift string")
        for position in range(start, i):
            if masked[position] != "\n":
                masked[position] = " "
    clean = "".join(masked)
    declarations = list(re.finditer(r"\bfinal\s+class\s+" + CLASS + r"\s*:\s*\w+\s*\{", clean))
    if len(declarations) != 1:
        raise ValueError(f"Expected exactly one {CLASS} declaration, found {len(declarations)}")
    match = declarations[0]
    depth = 1
    for end in range(match.end(), len(clean)):
        depth += (clean[end] == "{") - (clean[end] == "}")
        if depth == 0:
            return source[match.start():end + 1]
    raise ValueError("Unbalanced production class braces")


def digest(content):
    return hashlib.sha256(content).hexdigest()


def prepare(root, output, variant):
    root, output = root.resolve(), output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    interface = (root / INTERFACE).read_bytes()
    math = (root / MATH).read_bytes()
    extracted = extract_class(interface.decode("utf-8"))
    (output / "ProductionIndicator.swift").write_text(
        "import UIKit\nimport CoreLocation\n\n" + extracted + "\n", encoding="utf-8")
    (output / "MikshatNavigationMath.swift").write_bytes(math)
    shutil.copyfile(pathlib.Path(__file__).with_name("ProbeApp.swift"), output / "ProbeApp.swift")
    (output / "ProbeVariant.swift").write_text(f'let probeVariant = "{variant}"\n', encoding="utf-8")
    bundle = f"com.mikshat.arrowgeometry.{variant}"
    plist = {
        "CFBundleIdentifier": bundle,
        "CFBundleName": "Arrow Geometry",
        "CFBundleDisplayName": "Arrow Geometry " + variant,
        "CFBundleExecutable": "ArrowGeometryProbe",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0",
        "MinimumOSVersion": "27.0",
        "LSRequiresIPhoneOS": True,
        "UIDeviceFamily": [1],
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
        "UILaunchScreen": {},
        "UIApplicationSceneManifest": {
            "UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {
                "UIWindowSceneSessionRoleApplication": [{"UISceneConfigurationName": "Arrow Probe"}]
            },
        },
    }
    with (output / "Info.plist").open("wb") as handle:
        plistlib.dump(plist, handle)
    manifest = {
        "schema": 1, "variant": variant, "bundle_id": bundle,
        "source_root": str(root), "interface_path": str(INTERFACE), "math_path": str(MATH),
        "interface_sha256": digest(interface), "math_sha256": digest(math),
        "class_sha256": digest(extracted.encode("utf-8")),
        "class_byte_length": len(extracted.encode("utf-8")),
        "class_base": re.search(r"class\s+\w+\s*:\s*(\w+)", extracted).group(1),
        "extraction": "verbatim; imports only; no class, symbol, method, or algorithm replacement",
        "fixture_dependencies": ["MikshatStyle.green", "L", "MikshatHeading.location/reading"],
        "frameworks": ["UIKit", "CoreLocation"], "minimum_os": "27.0",
        "optimization": "-O -whole-module-optimization",
    }
    (output / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--variant", choices=("baseline", "fixed"), required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source_root, args.output, args.variant), indent=2))
