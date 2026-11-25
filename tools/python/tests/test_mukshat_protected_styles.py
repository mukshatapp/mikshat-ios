"""Check regenerated protected-area styles against a regenerated unmodified fork.

Usage: python3 test_mukshat_protected_styles.py --kothic tools/kothic/src \
  --baseline /path/to/original/data --current /path/to/modified/data --report result.json
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kothic', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--current', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('drules', args.kothic / 'drules.py')
    drules = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(drules)
    reserves = {'leisure-nature_reserve', 'boundary-national_park', 'boundary-protected_area'}
    reserves.update(f'boundary-protected_area-{i}' for i in range(1, 7))
    sand = {'natural-desert', 'natural-beach-sand'}
    checks = 0
    report = {'format': 'OMDR version 1', 'fill_opacity': 0.2,
              'light_rgb': '#7E3FB2', 'dark_rgb': '#B388E8',
              'daytime_sand_rgb': '#EBA426', 'families': {},
              'native_engine_built': False, 'android_opengl_tested': False}
    for family in ('default', 'outdoors', 'vehicle'):
        name = f'drules_{family}.bin'
        old_names, old = drules.parse_binary((args.baseline / name).read_bytes())
        names, current = drules.parse_binary((args.current / name).read_bytes())
        assert old_names == names == ['light', 'dark']
        summary = {'unchanged_other_type_rules': 0, 'protected_area_rules': 0, 'labels_preserved': 0}
        for variant, previous, result in zip(names, old, current):
            assert str(previous.colors) == str(result.colors), 'Unrelated GUI/named colors changed'
            baseline = {entry.name: entry for entry in previous.cont}
            updated = {entry.name: entry for entry in result.cont}
            assert baseline.keys() == updated.keys(), 'Classificator/style type set changed'
            for kind, entry in baseline.items():
                if kind not in reserves | sand:
                    assert str(entry) == str(updated[kind]), f'Unrelated rule changed: {family}/{variant}/{kind}'
                    summary['unchanged_other_type_rules'] += 1
                    checks += 1
            minimum = 10 if family == 'vehicle' else 8
            rgb = 0x7E3FB2 if variant == 'light' else 0xB388E8
            for kind in reserves:
                before = {element.scale: element for element in baseline[kind].element}
                after = {element.scale: element for element in updated[kind].element}
                for zoom in range(minimum, 21):
                    rule = after[zoom]
                    assert rule.area._is_set(), (family, variant, kind, zoom)
                    assert rule.area.color == 0xCC000000 | rgb
                    assert rule.area.border._is_set()
                    assert rule.area.border.color == rgb
                    assert rule.area.border.width == (1.5 if zoom < 14 else 2.0)
                    assert not rule.area.border.dashdot.dd and not rule.area.border.pathsym._is_set()
                    summary['protected_area_rules'] += 1
                    checks += 1
                for zoom, rule in before.items():
                    for field in ('symbol', 'caption', 'path_text', 'shield'):
                        assert str(getattr(rule, field)) == str(getattr(after[zoom], field)), (kind, zoom, field)
                    assert rule.apply_if == after[zoom].apply_if
                    summary['labels_preserved'] += 1
                    checks += 1
            for kind in sand:
                before = {element.scale: element for element in baseline[kind].element}
                after = {element.scale: element for element in updated[kind].element}
                for zoom, rule in after.items():
                    if not rule.area._is_set():
                        continue
                    if variant == 'light':
                        assert rule.area.color & 0xFFFFFF == 0xEBA426
                    if zoom in before and before[zoom].area._is_set():
                        assert (rule.area.color >> 24) == (before[zoom].area.color >> 24)
                        if variant == 'dark':
                            assert rule.area.color == before[zoom].area.color
                    checks += 1
        summary['sha256'] = hashlib.sha256((args.current / name).read_bytes()).hexdigest()
        summary['bytes'] = (args.current / name).stat().st_size
        report['families'][family] = summary
    for name in ('types.txt', 'classificator.txt'):
        assert (args.baseline / name).read_bytes() == (args.current / name).read_bytes(), name
    report['classification_unchanged'] = True
    report['checks_passed'] = checks
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
