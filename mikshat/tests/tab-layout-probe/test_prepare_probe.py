from pathlib import Path
import importlib.util
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('tab_probe', Path(__file__).with_name('prepare_probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
ROOT = Path(__file__).resolve().parents[3]


class PreparationTests(unittest.TestCase):
    def test_guarded_variant_prepares_only_inside_scroll_guard(self):
        source, changes = probe.guarded_variant((ROOT / probe.TAB).read_text())
        body = source[source.index('class TabView:'):]
        self.assertIn('let selectedIndex, hasContentItem(at: selectedIndex) {\n        tabsContentCollectionView.layoutIfNeeded()\n', body)
        self.assertNotIn('\n      tabsContentCollectionView.layoutIfNeeded()', body)
        self.assertIsInstance(changes, dict)

    def test_guarded_transform_is_idempotent(self):
        first, _ = probe.guarded_variant((ROOT / probe.TAB).read_text())
        second, _ = probe.guarded_variant(first)
        self.assertEqual(first, second)

    def test_as_is_keeps_actual_source_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            probe.prepare(ROOT, output, 'baseline', 'as-is')
            self.assertEqual((output / 'TabView.compiled.swift').read_bytes(), (ROOT / probe.TAB).read_bytes())
            self.assertIn('class TabView:', (output / 'Probe.swift').read_text())
            self.assertIn('class TabViewController:', (output / 'Probe.swift').read_text())

    def test_metrics_variant_invalidates_cached_delegate_sizes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            report = probe.prepare(ROOT, output, 'metrics', 'metrics')
            source = (output / 'TabView.compiled.swift').read_text()
            self.assertIn('invalidation.invalidateFlowLayoutDelegateMetrics = true', source)
            self.assertIn('invalidation.invalidateFlowLayoutAttributes = true', source)
            self.assertIn('tabsContentLayout.invalidateLayout(with: invalidation)', source)
            self.assertIn('let selectedIndex, hasContentItem(at: selectedIndex) {\n        tabsContentCollectionView.layoutIfNeeded()\n', source)
            self.assertEqual(report['variant'], 'metrics')


if __name__ == '__main__':
    unittest.main()
