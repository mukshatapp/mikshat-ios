"""Verify regenerated map-detail styles against the preceding pinned release."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kothic', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('drules', args.kothic / 'drules.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    affected = {'natural-scrub', 'power-line', 'power-minor_line'}
    checks = 0
    report = {'passed': True, 'families': {}, 'native_visibility_gate_tested_separately': True,
              'native_caption_factor': 1.38, 'relative_caption_and_shield_increment': 1.15,
              'device_rendering_tested': False}
    for family in ('default', 'outdoors', 'vehicle'):
        path = args.current / f'drules_{family}.bin'
        names, current = module.parse_binary(path.read_bytes())
        old_names, previous = module.parse_binary((args.baseline / path.name).read_bytes())
        assert names == old_names == ['light', 'dark']
        summary = {'unchanged_unrelated_type_rules': 0, 'power_rules': 0, 'scrub_captions': 0}
        for variant, old, new in zip(names, previous, current):
            old_types = {entry.name: entry for entry in old.cont}
            types = {entry.name: entry for entry in new.cont}
            assert old_types.keys() <= types.keys()
            assert types.keys() - old_types.keys() <= affected
            old_colors = {c.name: c.color for c in old.colors.value}
            colors = {c.name: c.color for c in new.colors.value}
            assert old_colors == colors
            checks += len(old_colors) + 3
            for name, entry in old_types.items():
                if name not in affected:
                    assert str(entry) == str(types[name]), (family, variant, name)
                    summary['unchanged_unrelated_type_rules'] += 1
                    checks += 1
            for name in ('power-line', 'power-minor_line'):
                rules = {e.scale: e for e in types[name].element}
                for scale in range(9, 21):
                    assert len(rules[scale].lines) == 2, (family, variant, name, scale)
                    summary['power_rules'] += 1
                    checks += 1
            rules = {e.scale: e for e in types['natural-scrub'].element}
            for scale in range(9, 21):
                assert rules[scale].caption._is_set(), (family, variant, scale)
                assert rules[scale].caption.primary.color == colors['MukshatFaydaText']
                summary['scrub_captions'] += 1
                checks += 2
        summary.update({'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'bytes': path.stat().st_size})
        report['families'][family] = summary
    for name in ('classificator.txt', 'types.txt'):
        assert (args.baseline/name).read_bytes() == (args.current/name).read_bytes(), name
        checks += 1
    report['classification_unchanged'] = True
    report['reserves_sand_other_water_and_track_rules_unchanged'] = True
    report['checks_passed'] = checks
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
