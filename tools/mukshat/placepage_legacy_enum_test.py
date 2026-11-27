#!/usr/bin/env python3
"""Run the native road-warning adapter against the retained Java enum consumer.

The JVM fixture reproduces the array access observed in the retained SDK's
MapObject constructor. This does not execute the Android APK or renderer.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def enum_source(text, name):
    match = re.search(r'enum class ' + name + r'\b[^\{]*\{(.*?)\};', text, re.S)
    if match is None:
        raise ValueError('Missing native enum ' + name)
    body = re.sub(r'//[^\n]*', '', match[1])
    values = {}
    value = -1
    for entry in body.split(','):
        entry = entry.strip()
        if not entry:
            continue
        if '=' in entry:
            key, number = entry.split('=', 1)
            value = int(number.strip(), 0)
        else:
            key = entry
            value += 1
        values[key.strip()] = value
    return 'enum class ' + name + ' : unsigned char {' + body + '};', values


def function_source(text, name):
    start = text.index('jint ' + name + '(')
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--override-root', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    contract_path = Path(__file__).with_name('legacy-placepage-enums.json')
    contract = json.loads(contract_path.read_text())
    cpp_relative = 'android/sdk/src/main/cpp/app/organicmaps/sdk/bookmarks/data/MapObject.cpp'
    cpp_path = (args.override_root or args.source_root) / cpp_relative
    native_path = args.source_root / 'libs/map/routing_mark.hpp'
    cpp = cpp_path.read_text()
    enum_definition, native_values = enum_source(native_path.read_text(), 'RoadWarningMarkType')
    adapter = function_source(cpp, 'ToJavaRoadWarningMarkType')
    if 'ToJavaRoadWarningMarkType(info.GetRoadType())' not in cpp:
        raise ValueError('The real MapObject constructor does not use the adapter')
    if 'static_cast<jint>(info.GetRoadType())' in cpp:
        raise ValueError('A raw native enum still reaches the legacy Java constructor')
    names = contract['road_warning_java_ordinals']
    ordered = [name for name, value in sorted(names.items(), key=lambda pair: pair[1])]
    if list(sorted(names.values())) != list(range(len(ordered))):
        raise ValueError('Invalid retained Java enum ordinal contract')
    cases = '\n'.join('  std::cout << "' + name + ' " << ' + str(value)
                      + ' << " " << ToJavaRoadWarningMarkType(RoadWarningMarkType::' + name + ') << "\\n";'
                      for name, value in native_values.items())
    harness = '#include <cstdlib>\n#include <iostream>\nusing jint = int;\n#define UNREACHABLE() std::abort()\n'
    harness += enum_definition + '\n' + adapter + '\nint main() {\n' + cases + '\n}\n'
    java = '''import java.nio.file.*;
public final class LegacyPlacePageEnumTest {
  enum Warning { ENUM_VALUES }
  static final class LegacyMapObject {
    final Warning warning;
    LegacyMapObject(int roadWarnType) { warning = Warning.values()[roadWarnType]; }
  }
  public static void main(String[] args) throws Exception {
    int verified = 0, priorFailures = 0;
    for (String line : Files.readAllLines(Path.of(args[0]))) {
      String[] fields = line.split(" ");
      String nativeName = fields[0];
      int raw = Integer.parseInt(fields[1]), mapped = Integer.parseInt(fields[2]);
      String expected = switch (nativeName) {
        case "Toll" -> "TOLL"; case "Ferry" -> "FERRY"; case "Dirty" -> "DIRTY";
        case "Steps" -> "STEPS"; case "Gate" -> "GATE"; case "LiftGate" -> "LIFT_GATE";
        default -> "UNKNOWN";
      };
      if (!new LegacyMapObject(mapped).warning.name().equals(expected))
        throw new AssertionError("Wrong legacy semantic for " + nativeName);
      verified++;
      if (nativeName.equals("Count") || nativeName.equals("ExpertTrail")) {
        try { new LegacyMapObject(raw); throw new AssertionError("Baseline regression not reproduced"); }
        catch (ArrayIndexOutOfBoundsException expectedFailure) { priorFailures++; }
      }
    }
    if (priorFailures != 2 || verified != 9) throw new AssertionError("Incomplete matrix");
    System.out.println("PASS retained Java constructor: " + verified + " native enum cases; "
                       + priorFailures + " prior bounds failures reproduced");
  }
}
'''.replace('ENUM_VALUES', ', '.join(ordered))
    compiler = shutil.which('g++') or shutil.which('clang++')
    if compiler is None:
        raise ValueError('A host C++ compiler is required')
    with tempfile.TemporaryDirectory(prefix='mukshat-placepage-enum-') as tmp:
        work = Path(tmp)
        (work / 'native.cpp').write_text(harness)
        outputs = {}
        for mode in ('legacy', 'modern'):
            command = [compiler, '-std=c++23', '-Wall', '-Wextra', '-Werror', str(work / 'native.cpp'),
                       '-o', str(work / mode)]
            if mode == 'legacy':
                command.insert(1, '-DMUKSHAT_LEGACY_SDK_ABI=1')
            subprocess.run(command, check=True)
            lines = subprocess.check_output([str(work / mode)], text=True)
            outputs[mode] = [line.split() for line in lines.splitlines()]
            (work / (mode + '.txt')).write_text(lines)
        for name, raw, mapped in outputs['modern']:
            if raw != mapped:
                raise ValueError('Modern SDK semantic changed: ' + name)
        (work / 'LegacyPlacePageEnumTest.java').write_text(java)
        subprocess.run(['java', '-m', 'jdk.compiler/com.sun.tools.javac.Main', '-d', str(work),
                        str(work / 'LegacyPlacePageEnumTest.java')], check=True)
        java_result = subprocess.check_output(['java', '-cp', str(work), 'LegacyPlacePageEnumTest',
                                               str(work / 'legacy.txt')], text=True).strip()
    report = {
        'passed': True,
        'legacy_native_values_tested': len(outputs['legacy']),
        'modern_identity_values_tested': len(outputs['modern']),
        'baseline_java_array_bounds_failures_reproduced': ['Count=8', 'ExpertTrail=7'],
        'jvm_consumer_result': java_result,
        'legacy_values': outputs['legacy'],
        'native_source_sha256': hashlib.sha256(cpp.encode()).hexdigest(),
        'native_enum_source_sha256': hashlib.sha256(native_path.read_bytes()).hexdigest(),
        'contract_sha256': hashlib.sha256(contract_path.read_bytes()).hexdigest(),
        'android_apk_runtime_tested': False,
        'fixture_scope': 'Host-compiled actual native adapter; JVM legacy constructor array access from observed SDK bytecode.'
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
