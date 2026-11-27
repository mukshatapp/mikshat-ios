"""Verify regenerated geography styles and unrelated-type preservation."""
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
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    reserves = {'leisure-nature_reserve', 'boundary-national_park', 'boundary-protected_area'}
    reserves.update(f'boundary-protected_area-{i}' for i in range(1, 7))
    early = {'place-locality', 'place-hamlet', 'place-village', 'natural-peak', 'natural-volcano',
             'natural-saddle', 'natural-cave_entrance', 'natural-rock',
             'man_made-cairn', 'man_made-water_well', 'amenity-drinking_water', 'amenity-water_point',
             'tourism-camp_site', 'tourism-picnic_site', 'tourism-viewpoint',
             'historic-archaeological_site', 'historic-ruins', 'natural-wetland',
             'natural-grassland', 'landuse-meadow'}
    waters = {'waterway-river', 'waterway-stream', 'waterway-canal', 'waterway-fish_pass'}
    changes = reserves | early | waters | {'highway-track'}

    def is_changed(name):
        return any(name == prefix or name.startswith(prefix + '-') for prefix in changes)

    checks = 0
    report = {'passed': True, 'format': 'OMDR version1', 'families': {},
              'nominal_saudi_ruler_km': {'50': 8, '20': 9, '10': 10},
              'reserve_fill_opacity_targets': {'8': 0.2, '9': 0.12, '10_and_closer': 0.04},
              'native_caption_size_factor': 1.2, 'native_name_override_tested_separately': True,
              'actual_android_rendering_tested': False}
    for family in ('default', 'outdoors', 'vehicle'):
        path = args.current / f'drules_{family}.bin'
        names, current = module.parse_binary(path.read_bytes())
        old_names, previous = module.parse_binary((args.baseline / path.name).read_bytes())
        assert names == old_names == ['light', 'dark']
        summary = {'unchanged_unrelated_type_rules': 0, 'reserve_rules': 0,
                   'solid_waterway_rules': 0, 'solid_track_rules': 0, 'early_detail_rules': 0}
        for variant, old, new in zip(names, previous, current):
            old_types = {entry.name: entry for entry in old.cont}
            types = {entry.name: entry for entry in new.cont}
            assert old_types.keys() <= types.keys(), 'Previously styled types disappeared'
            assert all(is_changed(name) for name in types.keys() - old_types.keys()), 'Unrelated styled type added'
            summary.setdefault('newly_visible_existing_types', sorted(types.keys() - old_types.keys()))
            old_colors = {c.name: c.color for c in old.colors.value}
            colors = {c.name: c.color for c in new.colors.value}
            assert all(colors[name] == color for name, color in old_colors.items())
            assert set(colors) - set(old_colors) == {
                'MukshatDirtRoad', 'MukshatFaydaText', 'MukshatReserveText', 'MukshatWaterText'}
            checks += len(old_colors) + 1
            for name, entry in old_types.items():
                if not is_changed(name):
                    assert str(entry) == str(types[name]), (family, variant, name)
                    summary['unchanged_unrelated_type_rules'] += 1
                    checks += 1
            for kind in reserves:
                rules = {e.scale: e for e in types[kind].element}
                assert not any(e.area._is_set() for e in types[kind].element if e.scale < 8)
                for zoom in range(8, 21):
                    e = rules[zoom]
                    assert e.area._is_set() and e.area.border._is_set()
                    assert e.area.priority == -999
                    assert e.area.color & 0xffffff == colors['MukshatReserveText']
                    opacity = 1 - (e.area.color >> 24) / 255
                    target = 0.2 if zoom == 8 else 0.12 if zoom == 9 else 0.04
                    assert abs(opacity - target) <= 1 / 255
                    assert e.area.border.color == colors['MukshatReserveText']
                    assert not e.area.border.dashdot.dd
                    assert e.caption.primary.color == colors['MukshatReserveText']
                    assert e.caption.primary.offset_y != 0
                    summary['reserve_rules'] += 1
                    checks += 8
            for name, entry in types.items():
                water = any(name == t or name.startswith(t + '-') for t in waters)
                track = name == 'highway-track' or name.startswith('highway-track-')
                if not water and not track:
                    continue
                if name.endswith('-tunnel'):
                    continue
                rules = {e.scale: e for e in entry.element}
                for zoom in range(9, 21):
                    e = rules[zoom]
                    role = 'MukshatWaterText' if water else 'MukshatDirtRoad'
                    assert e.lines, (family, name, zoom)
                    for line in e.lines:
                        assert line.color == colors[role], (family, name, zoom, line.color, colors[role])
                        assert not line.dashdot.dd, (family, name, zoom)
                        checks += 2
                    assert e.path_text._is_set() and e.path_text.primary.color == colors[role]
                    summary['solid_waterway_rules' if water else 'solid_track_rules'] += 1
                    checks += 1
            for name in early:
                rule = next(e for e in types[name].element if e.scale == 9)
                assert rule.caption._is_set() or rule.path_text._is_set(), (family, name)
                summary['early_detail_rules'] += 1
                checks += 1
            for name in ('natural-desert', 'natural-beach-sand'):
                before = {e.scale: e for e in old_types[name].element}
                for e in types[name].element:
                    if e.area._is_set():
                        assert e.area.color == before[e.scale].area.color
                        assert e.area.priority < -1000
                        checks += 2
        summary['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        summary['bytes'] = path.stat().st_size
        report['families'][family] = summary
    for name in ('types.txt', 'classificator.txt'):
        assert (args.baseline / name).read_bytes() == (args.current / name).read_bytes(), name
        checks += 1
    report['classification_unchanged'] = True
    report['checks_passed'] = checks
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
