import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('satellite', ROOT / 'mikshat/prepare_satellite.py')
satellite = importlib.util.module_from_spec(spec)
spec.loader.exec_module(satellite)
SOURCE = ROOT / 'iphone/Maps/Resources/Mikshat/GOOGLE.sqlitedb'


class SatelliteSourceTests(unittest.TestCase):
    def test_clean_read_only_checkout_needs_no_sqlite_sidecars(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'checkout # source'
            folder.mkdir()
            copy = folder / 'GOOGLE.sqlitedb'
            copy.write_bytes(SOURCE.read_bytes())
            copy.chmod(0o444)
            folder.chmod(0o555)
            try:
                source = satellite.configuration(copy)
                self.assertEqual(source['embeddedTileCount'], 0)
                self.assertEqual(list(folder.iterdir()), [copy])
            finally:
                folder.chmod(0o755)
                copy.chmod(0o644)

    def test_bundled_definition_uses_https_xyz_without_embedded_coverage(self):
        source = satellite.configuration(SOURCE)
        self.assertEqual((source['minZoom'], source['maxZoom']), (0, 20))
        self.assertEqual(source['embeddedTileCount'], 0)
        self.assertEqual(source['title'], 'قمر صناعي قوقل')
        self.assertTrue(source['url'].startswith('https://mt0.google.com/vt/'))
        self.assertIn('x={x}&y={y}&z={z}', source['url'])

    def test_invalid_source_is_rejected_before_packaging(self):
        for column, value in [('minzoom', '-1'), ('maxzoom', '21'),
                              ('inverted_y', '1'), ('ellipsoid', '1'),
                              ('url', 'https://example.com/{0}/{1}/{2}')]:
            with self.subTest(column=column), tempfile.TemporaryDirectory() as directory:
                copy = Path(directory) / 'source.db'
                copy.write_bytes(SOURCE.read_bytes())
                with sqlite3.connect(copy) as connection:
                    connection.execute('PRAGMA journal_mode=DELETE')
                    connection.execute(f'UPDATE info SET {column}=?', (value,))
                with self.assertRaises(ValueError):
                    satellite.configuration(copy)


if __name__ == '__main__':
    unittest.main()
