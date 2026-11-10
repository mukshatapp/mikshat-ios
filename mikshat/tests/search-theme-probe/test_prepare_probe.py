import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prepare_probe', HERE / 'prepare_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbePreparationTests(unittest.TestCase):
    def test_preserves_override_declaration_and_method_body(self):
        method = '''  @objc override func sw_didMoveToWindow() {
    // This comment has a } that is not a brace.
    guard window != nil else { sw_didMoveToWindow(); return }
    print("a { brace in a string }")
    sw_didMoveToWindow()
  }'''
        name, extracted = probe.extract_hook('extension UITextField {\n' + method + '\n}\n')
        self.assertEqual(name, 'sw_didMoveToWindow')
        self.assertEqual(extracted, method)

    def test_rejects_missing_or_ambiguous_hook_source(self):
        with self.assertRaises(ValueError):
            probe.extract_hook('extension UIView {}')
        with self.assertRaises(ValueError):
            probe.extract_hook('  func sw_a() {}\n  func sw_b() {}')

    def test_generated_app_contains_the_actual_source_methods(self):
        root = HERE.parents[2]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = probe.prepare(root, output, 'checked')
            generated = (output / 'Probe.swift').read_text()
            for path in probe.FILES.values():
                _, method = probe.extract_hook((root / path).read_text())
                self.assertIn(method, generated)
            source = root / 'iphone/Maps/Core/Theme/Swizzle'
            self.assertEqual((output / 'SwizzleStyle.m').read_bytes(), (source / 'SwizzleStyle.m').read_bytes())
            self.assertEqual(set(manifest['selectors']), {'UIView', 'UITextField', 'UISearchBar'})
            self.assertNotIn('__LABEL__', generated)
            self.assertNotIn('__REINSTALL__', generated)


if __name__ == '__main__':
    unittest.main()
