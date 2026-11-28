"""Compile the actual framework selection function against recording native boundaries.

This is a host behavior test; full native CI builds compile the function in context.
It does not certify Android rendering or an actual device session.
"""
from pathlib import Path
import argparse
import hashlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--framework', type=Path, default=ROOT/'libs/map/framework.cpp')
    args = parser.parse_args()
    source = args.framework.read_text()
    begin = source.index('void Framework::OnTapEvent(place_page::BuildInfo const & buildInfo)')
    end = source.index('\nvoid Framework::InvalidateRendering()', begin)
    function = source[begin:end].strip()
    fixture = (Path(__file__).parent/'history_browse_fixture.cpp').read_text()
    marker = '// MUKSHAT_ACTUAL_ON_TAP_FUNCTION'
    assert fixture.count(marker) == 1
    with tempfile.TemporaryDirectory(prefix='mukshat-native-history-') as directory:
        work = Path(directory)
        cpp, binary = work/'actual-selection.cpp', work/'actual-selection'
        cpp.write_text(fixture.replace(marker, function))
        for mode in ['legacy', 'modern']:
            defines = ['-DMUKSHAT_LEGACY_SDK_ABI=1'] if mode == 'legacy' else []
            subprocess.run(['c++', '-std=c++17', '-Wall', '-Wextra', '-Werror', *defines,
                            str(cpp), '-o', str(binary)], check=True)
            print('Build mode: '+mode, flush=True)
            subprocess.run([str(binary)], check=True)
    print('Framework SHA256 '+hashlib.sha256(source.encode()).hexdigest())


if __name__ == '__main__':
    main()
