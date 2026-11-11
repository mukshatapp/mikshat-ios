import datetime
import pathlib
import struct
import tempfile
import unittest

from inspect_mwm import InvalidMwm, inspect


def vu(value):
    output = bytearray()
    while value >= 128:
        output.append((value & 127) | 128)
        value >>= 7
    output.append(value)
    return bytes(output)


def container(sections):
    output, table = bytearray(b"\0" * 8), bytearray(vu(len(sections)))
    for tag, data in sorted(sections.items()):
        offset = len(output)
        output.extend(data)
        table.extend(vu(len(tag)) + tag.encode("ascii") + vu(offset) + vu(len(data)))
    struct.pack_into("<Q", output, 0, len(output))
    return output + table


class InspectMwmTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = pathlib.Path(self.directory.name) / "test.mwm"
        epoch = int(datetime.datetime(2026, 7, 14, tzinfo=datetime.timezone.utc).timestamp())
        self.sections = {
            "version": b"MWM\0" + vu(10) + vu(epoch),
            "header": vu(30) + vu(0) + vu(0) + vu(0) + vu(4) + bytes((10, 12, 14, 17)) + vu(0) + vu(4),
            "features": b"x", "idx": b"x", "geom0": b"x", "geom1": b"", "geom2": b"", "geom3": b"",
            "offs": b"x", "rgninfo": b"x",
            "sdx": struct.pack("<BII", 2, 9, 1) + b"x",
            "routing": struct.pack("<BIII", 0, 1, 1, 1) + struct.pack("<QIIII", 1, 1, 0, 1, 7) + b"x",
            "cross_mwm": struct.pack("<I", 2),
        }

    def write(self):
        self.path.write_bytes(container(self.sections))

    def test_country_header_and_version(self):
        self.write()
        report = inspect(self.path, expected_version=260714, country=True)
        self.assertEqual(report["header"]["map_type"], "Country")
        self.assertEqual(report["routing_header"]["vehicle_masks"], [7])

    def test_html_is_rejected(self):
        self.path.write_bytes(b"<!doctype html><html>Download quota exceeded</html>")
        with self.assertRaises(InvalidMwm):
            inspect(self.path)

    def test_truncation_is_rejected(self):
        self.write()
        self.path.write_bytes(self.path.read_bytes()[:-1])
        with self.assertRaises(InvalidMwm):
            inspect(self.path)

    def test_wrong_version_and_size_are_rejected(self):
        self.write()
        with self.assertRaises(InvalidMwm):
            inspect(self.path, expected_version=260715)
        with self.assertRaises(InvalidMwm):
            inspect(self.path, expected_size=1)

    def test_missing_search_is_rejected_for_country(self):
        del self.sections["sdx"]
        self.write()
        with self.assertRaises(InvalidMwm):
            inspect(self.path, country=True)

    def test_missing_indexed_geometry_is_rejected(self):
        del self.sections["geom2"]
        self.sections["geom"] = b"x"
        self.write()
        with self.assertRaises(InvalidMwm):
            inspect(self.path, country=True)

    def test_search_range_is_rejected(self):
        self.sections["sdx"] = struct.pack("<BII", 2, 9, 999) + b"x"
        self.write()
        with self.assertRaises(InvalidMwm):
            inspect(self.path, country=True)

    def test_unknown_format_is_rejected(self):
        self.sections["version"] = b"MWM\0" + vu(11) + vu(0)
        self.write()
        with self.assertRaises(InvalidMwm):
            inspect(self.path)

    def test_unbounded_table_count_is_rejected(self):
        self.path.write_bytes(struct.pack("<Q", 8) + vu(2**32 - 1))
        with self.assertRaises(InvalidMwm):
            inspect(self.path)


if __name__ == "__main__":
    unittest.main()
