#!/usr/bin/env python3
"""Bounded MWM container inspection; does not execute native search or routing."""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import struct
import sys


class InvalidMwm(ValueError):
    pass


class Source:
    """Read a bounded view without loading map sections into memory."""

    def __init__(self, stream, start, size):
        self.stream, self.start, self.size, self.pos = stream, start, size, 0

    def read(self, count):
        if count < 0 or count > self.size - self.pos:
            raise InvalidMwm("read outside section")
        self.stream.seek(self.start + self.pos)
        value = self.stream.read(count)
        if len(value) != count:
            raise InvalidMwm("truncated file")
        self.pos += count
        return value

    def uint(self, bits=64):
        value = 0
        for shift in range(0, bits, 7):
            byte = self.read(1)[0]
            value |= (byte & 127) << shift
            if not byte & 128:
                if value >= 1 << bits:
                    raise InvalidMwm("varuint overflow")
                return value
        raise InvalidMwm("unterminated or overflowing varuint")

    def sint(self, bits=64):
        value = self.uint(bits)
        return (value >> 1) ^ -(value & 1)

    def unpack(self, fmt):
        return struct.unpack(fmt, self.read(struct.calcsize(fmt)))


def _version(src):
    if src.read(4) != b"MWM\x00":
        raise InvalidMwm("invalid MWM version prolog")
    format_number, epoch = src.uint(32), src.uint(32)
    if format_number != 10:
        raise InvalidMwm(f"unsupported format {format_number + 1}; this checkout uses v11")
    date = datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc)
    return {"format": format_number + 1, "epoch_seconds": epoch,
            "data_version": int(date.strftime("%y%m%d")), "utc": date.isoformat()}


def _header(src):
    coord_bits, base_point = src.uint(32), src.uint()
    if not 0 < coord_bits < 32:
        raise InvalidMwm("invalid geometry coordinate bits")
    bounds = [src.sint(), src.sint()]
    scale_count = src.uint(32)
    if scale_count != 4:
        raise InvalidMwm("header must have four geometry scales")
    scales = list(src.read(scale_count))
    language_count = src.uint(32)
    if language_count > 256:
        raise InvalidMwm("unreasonable header language count")
    languages = list(src.read(language_count))
    map_type = src.sint(32)
    if map_type not in (0, 1, 2):
        raise InvalidMwm("invalid map type")
    return {"map_type": ("World", "WorldCoasts", "Country")[map_type],
            "coordinate_bits": coord_bits, "base_point": base_point,
            "encoded_bounds": bounds, "scales": scales, "languages": languages}


def _search(src):
    version, offset, size = src.unpack("<BII")
    if version != 2:
        raise InvalidMwm(f"unsupported search header {version}")
    if offset < 9 or not size or size > src.size - offset:
        raise InvalidMwm("search index outside section")
    return {"version": version, "index_offset": offset, "index_size": size}


def _routing(src):
    version, roads, joints, count = src.unpack("<BIII")
    if version != 0:
        raise InvalidMwm(f"unsupported routing header {version}")
    if count > 64:
        raise InvalidMwm("unreasonable routing subsection count")
    payload_size, masks = 0, []
    for _ in range(count):
        size, section_roads, begin, end, mask = src.unpack("<QIIII")
        if begin > end or end > joints or section_roads > roads:
            raise InvalidMwm("invalid routing subsection counts")
        payload_size += size
        masks.append(mask)
    if payload_size > src.size - src.pos:
        raise InvalidMwm("routing subsections outside section")
    return {"version": version, "roads": roads, "joints": joints,
            "subsection_count": count, "vehicle_masks": masks}


def inspect(path, expected_version=None, expected_size=None, country=False):
    path = Path(path)
    size = path.stat().st_size
    if expected_size is not None and size != expected_size:
        raise InvalidMwm(f"file size {size} != expected {expected_size}")
    if size < 9:
        raise InvalidMwm("file too small for a container")
    with path.open("rb") as stream:
        table_offset = struct.unpack("<Q", stream.read(8))[0]
        if not 8 <= table_offset < size:
            raise InvalidMwm("invalid section table offset (possibly HTML or truncated download)")
        table = Source(stream, table_offset, size - table_offset)
        count = table.uint(32)
        if not 1 <= count <= 512:
            raise InvalidMwm("unreasonable section count")
        sections = {}
        previous_tag = ""
        for _ in range(count):
            tag_size = table.uint(32)
            if not 1 <= tag_size <= 128:
                raise InvalidMwm("invalid section tag size")
            try:
                tag = table.read(tag_size).decode("ascii")
            except UnicodeDecodeError as error:
                raise InvalidMwm("non-ASCII section tag") from error
            if tag <= previous_tag:
                raise InvalidMwm("duplicate or unsorted section tag")
            previous_tag = tag
            offset, section_size = table.uint(), table.uint()
            if offset < 8 or offset > table_offset or section_size > table_offset - offset:
                raise InvalidMwm(f"section {tag} outside payload")
            sections[tag] = {"offset": offset, "size": section_size}
        if table.pos != table.size:
            raise InvalidMwm("unexpected bytes after section table")
        occupied = sorted((s["offset"], s["offset"] + s["size"]) for s in sections.values() if s["size"])
        if any(left[1] > right[0] for left, right in zip(occupied, occupied[1:])):
            raise InvalidMwm("overlapping sections")

        def section(tag):
            if tag not in sections or not sections[tag]["size"]:
                raise InvalidMwm(f"missing or empty section {tag}")
            return Source(stream, sections[tag]["offset"], sections[tag]["size"])

        result = {"file": str(path), "file_size": size, "table_offset": table_offset,
                  "version": _version(section("version")), "header": _header(section("header")),
                  "sections": sections}
        version = result["version"]["data_version"]
        if expected_version is not None and version != expected_version:
            raise InvalidMwm(f"data version {version} != expected {expected_version}")
        if country:
            if result["header"]["map_type"] != "Country":
                raise InvalidMwm("expected a country map")
            for tag in ("features", "idx", "offs", "rgninfo", "cross_mwm"):
                section(tag)
            # GetTagForIndex(GEOMETRY_FILE_TAG, i), not a bare "geom" tag.
            # A scale may contain no geometry, so empty indexed sections are legal.
            for index in range(4):
                if f"geom{index}" not in sections:
                    raise InvalidMwm(f"missing geometry section geom{index}")
            result["search_header"] = _search(section("sdx"))
            result["routing_header"] = _routing(section("routing"))
            cross_version, = section("cross_mwm").unpack("<I")
            if cross_version > 2:
                raise InvalidMwm(f"unsupported cross_mwm header {cross_version}")
            result["cross_mwm_version"] = cross_version
        digest = hashlib.sha256()
        stream.seek(0)
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
        result["sha256"] = digest.hexdigest()
        result["validation_scope"] = "container bounds and selected headers; native search/routing not executed"
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", type=Path, nargs="+")
    parser.add_argument("--expected-version", type=int)
    parser.add_argument("--expected-size", type=int)
    parser.add_argument("--country", action="store_true", help="require country, search and routing sections/headers")
    args = parser.parse_args()
    try:
        results = [inspect(path, args.expected_version, args.expected_size, args.country) for path in args.files]
    except (OSError, InvalidMwm) as error:
        print(f"MWM validation failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
