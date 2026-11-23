#!/usr/bin/env python3
"""Generate Mikshat's Arabic/English interface with the project's Twine formatters.

The small iOS terminology overlay keeps app wording independent of the shared
Android, map-type, and spoken-direction catalogs.
"""

import argparse
import copy
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
LANGUAGES = ("ar", "en")
sys.path.insert(0, str(ROOT / "tools/python/twine/python_twine"))

from twine import TwineError
from twine.formatters.registry import get_registry
from twine.twine_file import TwineFile


def load_interface_strings():
    strings = TwineFile()
    strings.read(str(ROOT / "data/strings/strings.txt"))
    overlay = TwineFile()
    overlay.read(str(ROOT / "data/strings/ios_mikshat.txt"))
    for key, override in overlay.definitions_by_key.items():
        definition = strings.definitions_by_key.get(key)
        if definition is None:
            raise TwineError(f"iOS terminology override references an unknown key: {key}")
        if set(override.translations) != set(LANGUAGES) or override.is_plural():
            raise TwineError(f"iOS terminology override must provide Arabic and English: {key}")
        definition.translations.update(override.translations)
    return strings


def generate(output_root, check=False):
    strings = load_interface_strings()
    types = TwineFile()
    types.read(str(ROOT / "data/strings/types_strings.txt"))
    resources = (
        (strings, "apple", "apple-maps", "Localizable.strings"),
        (strings, "apple-plural", "apple-maps", "Localizable.stringsdict"),
        (strings, "apple", "apple-infoplist", "InfoPlist.strings"),
        (types, "apple", None, "LocalizableTypes.strings"),
    )
    mismatches = []
    for catalog, format_name, tag, filename in resources:
        formatter = copy.deepcopy(get_registry().get(format_name))
        formatter.twine_file = catalog
        formatter.options = {"include": "all", "untagged": True}
        if tag:
            formatter.options["tags"] = [[tag]]
        for language in LANGUAGES:
            path = output_root / f"{language}.lproj" / filename
            content = formatter.format_file(language)
            if not content:
                raise TwineError(f"No translations generated for {path}")
            if check:
                if not path.is_file() or path.read_text(encoding="utf-8") != content:
                    mismatches.append(path)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
                print(f"Generated {path}")
    if mismatches:
        raise TwineError("Stale iOS localizations: " + ", ".join(map(str, mismatches)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify generated files without changing them")
    parser.add_argument("--output-root", type=Path, default=ROOT / "iphone/Maps/LocalizedStrings")
    args = parser.parse_args()
    generate(args.output_root, check=args.check)


if __name__ == "__main__":
    main()
