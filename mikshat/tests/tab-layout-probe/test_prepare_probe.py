from pathlib import Path
import hashlib
import importlib.util
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('tab_probe', Path(__file__).with_name('prepare_probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
ROOT = Path(__file__).resolve().parents[3]


class PreparationTests(unittest.TestCase):
    def test_as_is_compiles_exact_production_files_and_records_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            report = probe.prepare(ROOT, output, 'current', 'as-is')
            source = (ROOT / probe.TAB).read_bytes()
            controller = (ROOT / probe.CONTROLLER).read_bytes()
            self.assertEqual((output / 'TabView.compiled.swift').read_bytes(), source)
            self.assertEqual((output / 'TabViewController.original.swift').read_bytes(), controller)
            self.assertEqual(report['originalSHA256'], hashlib.sha256(source).hexdigest())
            self.assertEqual(report['compiledSHA256'], report['originalSHA256'])
            self.assertEqual(report['controllerSHA256'], hashlib.sha256(controller).hexdigest())
            self.assertIsNone(report['transform'])
            app = (output / 'Probe.swift').read_text()
            self.assertIn(source.decode(), app)
            self.assertIn(controller.decode(), app)

    def test_optional_trace_records_exact_instrumented_source(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            report = probe.prepare(ROOT, output, 'trace', 'as-is', trace_layout=True)
            traced = (output / 'TabView.compiled.swift').read_bytes()
            self.assertTrue(report['traceLayout'])
            self.assertFalse(report['transform']['trace']['layoutBehaviorChanged'])
            self.assertEqual(report['compiledSHA256'], hashlib.sha256(traced).hexdigest())
            for stage in ['parent-entry', 'parent-after-super', 'parent-compare', 'layout-identity', 'delegate-size']:
                self.assertIn('probeTrace("' + stage + '"', traced.decode())

    def test_experimental_layout_transformations_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'compiles source as-is'):
                probe.prepare(ROOT, Path(directory), 'unsupported', 'experimental')


if __name__ == '__main__':
    unittest.main()
