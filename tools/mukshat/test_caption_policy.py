"""Compile the actual selected-name renderer body with narrow name-provider fixtures."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import resource


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-source", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source = root / 'libs/drape_frontend/stylist.cpp'
    text = source.read_text()
    start = text.index('void CaptionDescription::Init(')
    end = text.index('\nvoid Stylist::ProcessKey', start)
    body = text[start:end]
    assert 'PopulateUnnamedCaption' not in text
    assert 'ArabicMapCaptionForType' not in text
    assert 'GenericCaptionType' not in body
    assert 'm_mainText = out.GetPrimary();' in body
    assert 'm_auxText = out.secondary;' in body
    fixture = (root / 'tools/mukshat/caption_fallback_test.cpp').read_text()
    assert fixture.count('// INSERT_ACTUAL_CAPTION_INIT') == 1
    compiled = fixture.replace('// INSERT_ACTUAL_CAPTION_INIT', body)
    with tempfile.TemporaryDirectory(prefix='mukshat-caption-policy-') as temp:
        cpp = Path(temp) / 'caption_policy.cpp'
        executable = Path(temp) / 'caption_policy'
        cpp.write_text(compiled)
        subprocess.run(['g++', '-std=c++23', '-Wall', '-Wextra', '-Werror',
                        '-DMUKSHAT_LEGACY_SDK_ABI', '-I', str(root / 'libs'), str(cpp), '-o', str(executable)],
                       check=True, capture_output=True, text=True)
        result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
        baseline = None
        if args.baseline_source:
            baseline_text = args.baseline_source.read_text()
            begin = baseline_text.index('void CaptionDescription::Init(')
            finish = baseline_text.index('\nvoid Stylist::ProcessKey', begin)
            cpp.write_text(fixture.replace('// INSERT_ACTUAL_CAPTION_INIT', baseline_text[begin:finish]))
            subprocess.run(['g++', '-std=c++23', '-Wall', '-Wextra', '-Werror',
                            '-DMUKSHAT_LEGACY_SDK_ABI', '-I', str(root / 'libs'), str(cpp), '-o', str(executable)],
                           check=True, capture_output=True, text=True)
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            failed = subprocess.run([str(executable)], capture_output=True, text=True)
            assert failed.returncode == -6 and 'm_mainText.empty()' in failed.stderr
            baseline = {'sha256': hashlib.sha256(args.baseline_source.read_bytes()).hexdigest(),
                        'previous_generic_caption_assertion_fails': True, 'return_code': failed.returncode}

    print(json.dumps({'passed': True, 'actual_init_function_compiled': True,
                      'synthesized_caption_insertion_removed': True,
                      'actual_selected_names_preserved_without_text_matching': True,
                      'stylist_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                      'fixture_scope': 'Actual renderer CaptionDescription::Init body; FeatureType name-provider and region stubs, not device rendering.',
                      'native_result': result.stdout.strip(), 'baseline_counterexample': baseline}, ensure_ascii=False))


if __name__ == '__main__':
    main()
