"""Compile the actual transit symbol table and validate every legacy atlas lookup."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--assets-root', type=Path)
    parser.add_argument('--reference-root', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    assets = args.assets_root or args.source_root / 'data'
    header = args.source_root / 'libs/map/transit/transit_display.hpp'
    if not header.is_file() and args.reference_root:
        header = args.reference_root / 'libs/map/transit/transit_display.hpp'
    text = header.read_text()
    start = text.index('enum class TransitType')
    enum = text[start:text.index('};', start) + 2]
    text = (args.source_root / 'libs/map/transit/transit_display.cpp').read_text()
    start = text.index('std::map<TransitType, std::string> const kTransitSymbols')
    table = text[start:text.index('\nstd::string DebugPrint(', start)]
    main = '\nint main() { for (auto const & [mode,name] : kTransitSymbols) std::cout << int(mode) << "|" << name << "\\n"; }\n'
    expected = {2: 'transit_subway', 3: 'transit_train', 4: 'transit_light_rail',
                5: 'transit_monorail', 6: 'transit_tram', 7: 'transit_bus',
                8: 'transit_ferry', 9: 'transit_cable_tram', 10: 'transit_aerial_lift',
                11: 'transit_funicular', 12: 'transit_bus', 13: 'transit_air_service',
                14: 'transit_water_service'}
    legacy_expected = dict(expected)
    legacy_expected.update({8: 'ship', 9: 'transit_tram', 10: 'cable-car',
                            11: 'funicular', 13: 'airport', 14: 'ship'})
    with tempfile.TemporaryDirectory(prefix='mukshat-transit-symbols-') as work:
        source = Path(work) / 'symbols.cpp'
        source.write_text('#include <cstdint>\n#include <iostream>\n#include <map>\n#include <string>\n' + enum + '\n' + table + main)
        for legacy in (False, True):
            binary = Path(work) / ('legacy' if legacy else 'modern')
            command = ['c++', '-std=c++20', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(binary)]
            if legacy:
                command.insert(1, '-DMUKSHAT_LEGACY_SDK_ABI')
            subprocess.run(command, check=True)
            result = subprocess.check_output([str(binary)], text=True)
            actual = {int(row.split('|')[0]): row.split('|')[1] for row in result.splitlines()}
            assert actual == (legacy_expected if legacy else expected)
            if legacy:
                legacy_names = set(actual.values())
    checks = 26
    atlases = []
    for density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi', '6plus']:
        for theme in ['light', 'dark']:
            folder = assets / 'symbols' / density / theme
            names = {node.attrib['name']: node.attrib for node in ET.parse(folder / 'symbols.xml').getroot().iter() if 'name' in node.attrib}
            png = (folder / 'symbols.png').read_bytes()
            assert png[:8] == b'\x89PNG\r\n\x1a\n'
            width, height = struct.unpack('>II', png[16:24])
            for base in legacy_names:
                for suffix in ['-s', '-m']:
                    name = base + suffix
                    assert name in names, (density, theme, name)
                    node = names[name]
                    assert 0 <= int(node['minX']) < int(node['maxX']) <= width
                    assert 0 <= int(node['minY']) < int(node['maxY']) <= height
                    checks += 3
            atlases.append({'density': density, 'theme': theme, 'width': width, 'height': height,
                            'required_symbols': len(legacy_names) * 2})
    report = {'verified': True, 'checks': checks, 'actual_source_tables_compiled': True,
              'modern_mapping_unchanged': True, 'legacy_modes': legacy_expected,
              'atlases': atlases, 'new_atlas_images_created': False,
              'android_transit_route_render_tested': False}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
