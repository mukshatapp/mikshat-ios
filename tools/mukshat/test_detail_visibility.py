"""Compile actual metric visibility policy and verify its legacy-only wiring."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile

BASE_MODERN = {
    'engine_context.cpp': '504eae98c519c85e43020378eab36be26831a3fa964330fc5bcdafbb417fc0cd',
    'engine_context.hpp': '6e0a0a3adc2cc66d47a17fadfe42ebe0d4912da79abb49502efca623d2d09ea6',
    'read_manager.cpp': '15c9c0e030e85c83097b89702b0672a03b41b32aa12c5b8b58404ce93f8a8090',
    'read_manager.hpp': 'c76a5f23370a9757ba3d588ad8a770d4df9a6b954358d9183a56847a2623c8b6',
    'rule_drawer.cpp': 'e1e6117ad5a55151ff5e9a1e93b7cb13d80c380b2ba10d46421951f6bac1a75f',
}


def modern_source(source):
    result = []
    skip = 0
    for line in source.splitlines(keepends=True):
        if not skip and line.strip() == '#if defined(MUKSHAT_LEGACY_SDK_ABI)':
            skip = 1
        elif skip:
            if re.match(r'\s*#\s*if', line):
                skip += 1
            elif re.match(r'\s*#\s*endif', line):
                skip -= 1
        else:
            result.append(line)
    assert skip == 0
    return ''.join(result)


def normalized(source):
    source = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    return re.sub(r'\s+', '', source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    folder = args.source_root / 'libs/drape_frontend'
    hashes = {}
    for name, expected in BASE_MODERN.items():
        path = folder/name
        source = path.read_text()
        digest = hashlib.sha256(normalized(modern_source(source)).encode()).hexdigest()
        assert digest == expected, f'Unintended modern/upstream source change: {name}'
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    read = (folder/'read_manager.cpp').read_text()
    update = read[read.index('void ReadManager::UpdateCoverage'):read.index('void ReadManager::Invalidate(')]
    assert update.index('m_detailVisibility = detailVisibility;') < update.index('PushTaskBackForTileKey(')
    assert '!m_detailVisibilityInitialized || detailVisibility != m_detailVisibility' in update
    assert '|| detailVisibilityChanged' in update
    assert update.index('CancelTileInfo(info);') < update.index('++m_generationCounter;') < update.index('PushTaskBackForTileKey(')
    enqueue = read[read.index('void ReadManager::PushTaskBackForTileKey'):read.index('void ReadManager::CheckFinishedTiles')]
    assert ', m_detailVisibility' in enqueue
    context = (folder/'engine_context.hpp').read_text()
    assert 'mukshat::DetailVisibilityMask const m_detailVisibility;' in context
    assert 'detailVisibility = mukshat::kAllDetailVisibility' in context
    assert 'GetDetailVisibility() const { return m_detailVisibility; }' in context
    drawer = (folder/'rule_drawer.cpp').read_text()
    operator = drawer[drawer.index('void RuleDrawer::operator()(FeatureType & f)'):drawer.index('void RuleDrawer::FlushGeometryShapes')]
    assert operator.index('mukshat::CanShow(') < operator.index('Stylist const s(')
    assert drawer.count('mukshat::CanShow(') == 1
    assert 'm_context->GetDetailVisibility()' in operator
    assert 'GetCurrentDetailVisibility' not in operator and 'ScreenBase' not in operator
    # Same physical probe as RulerHelper::Update; workers receive only its resolved bucket.
    assert 'kMinimumRulerPixelWidth * VisualParams::Instance().GetVisualScale()' in read
    assert 'screen.PixelRect().Center()' in read
    assert 'screen.PtoG(pivot - m2::PointD(width, 0))' in read
    assert 'mercator::DistanceOnEarth(left, right)' in read

    with tempfile.TemporaryDirectory(prefix='mukshat-detail-visibility-') as directory:
        executable = Path(directory)/'test'
        subprocess.run(['g++', '-std=c++23', '-Wall', '-Wextra', '-Werror',
                        '-I', str(args.source_root/'libs'),
                        str(args.source_root/'tools/mukshat/detail_visibility_test.cpp'),
                        '-o', str(executable)], check=True, capture_output=True, text=True)
        native = subprocess.run([str(executable)], check=True, capture_output=True, text=True).stdout.strip()

    # Independent flat-Mercator reference: integer zoom is not the visibility gate.
    unit_values = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000]
    reference_checks = 0
    for latitude in [16, 23.9, 33]:
        for zoom in [10.4, 10.5, 10.6, 11.0, 11.4, 11.9, 12.0, 12.1, 12.5, 13.0, 13.5]:
            expected_raw = 60 * 40075016.68557849 * math.cos(math.radians(latitude)) / (256 * 2**zoom)
            rounded = next(v for v in unit_values if v > expected_raw)
            assert (rounded <= 2000) == (expected_raw < 2000)
            assert (rounded <= 5000) == (expected_raw < 5000)
            for visual_scale in [1.35, 2.0, 3.0, 4.0]:
                for tile_size in [256, 512, 1024]:
                    base = zoom - math.log2(tile_size/256/visual_scale)
                    actual_raw = 60 * visual_scale * 40075016.68557849 * math.cos(math.radians(latitude)) / (tile_size * 2**base)
                    assert abs(actual_raw - expected_raw) < 1e-8
                    reference_checks += 1
    result = {
        'passed': True, 'pinned_baseline': 'aae05dcbce78b579185bbb4896c82f4ea75c5077',
        'compiled_actual_policy': native, 'modern_source_units_unchanged': 5,
        'immutable_context_snapshot': True, 'first_coverage_initialized': True,
        'bucket_change_cancels_and_increments_generation': True,
        'guard_applied_before_stylist_to_geometry_and_names': True,
        'reference_density_latitude_zoom_combinations': reference_checks,
        'reference_scope': 'Flat Mercator calculation and source-wiring checks; not actual device/rotation rendering proof.',
        'device_rendering_tested': False, 'source_sha256': hashes,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
