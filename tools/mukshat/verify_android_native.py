"""Verify legacy JNI exports and strong imports against the selected NDK API stubs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

TRIPLES = {'arm64-v8a': 'aarch64-linux-android', 'x86': 'i686-linux-android'}


def output(command):
    return subprocess.run([str(x) for x in command], check=True, text=True,
                          stdout=subprocess.PIPE).stdout


def symbols(readelf, library):
    defined, required = set(), set()
    for line in output([readelf, '--dyn-syms', '--wide', library]).splitlines():
        fields = line.split()
        if len(fields) < 8 or not fields[0].endswith(':') or not fields[0][:-1].isdigit():
            continue
        name = fields[7].split('@', 1)[0]
        if fields[6] != 'UND':
            defined.add(name)
        elif fields[4] == 'GLOBAL':
            required.add(name)
    return defined, required


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--ndk', type=Path, required=True)
    parser.add_argument('--abi', choices=TRIPLES, required=True)
    parser.add_argument('--api', type=int, default=21)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    toolchain = args.ndk/'toolchains/llvm/prebuilt/linux-x86_64'
    readelf = toolchain/'bin/llvm-readelf'
    stubs = toolchain/'sysroot/usr/lib'/TRIPLES[args.abi]/str(args.api)
    defined, required = symbols(readelf, args.library)
    needed = re.findall(r'Shared library: \[([^\]]+)\]', output([readelf, '-d', args.library]))
    supplied = set(defined)
    for name in needed:
        dependency = stubs/name
        if not dependency.is_file():
            raise SystemExit('Missing selected-API dependency stub: '+str(dependency))
        supplied.update(symbols(readelf, dependency)[0])
    unresolved = sorted(required-supplied)
    if unresolved:
        raise SystemExit('Imports unavailable at API'+str(args.api)+': '+', '.join(unresolved))
    root = Path(__file__).resolve().parents[2]
    contract = json.loads((root/'tools/mukshat/legacy-jni-contract.json').read_text())
    missing = []
    for key in contract:
        cls, method = key.rsplit('.', 1)
        symbol = 'Java_'+cls.replace('/', '_').replace('$', '_00024')+'_'+method
        if symbol not in defined:
            missing.append(symbol)
    if missing:
        raise SystemExit('Missing JNI exports: '+', '.join(missing))
    alignments = []
    for line in output([readelf, '-l', '--wide', args.library]).splitlines():
        fields = line.split()
        if fields and fields[0] == 'LOAD':
            alignments.append(int(fields[-1], 16))
    if not alignments or args.abi == 'arm64-v8a' and min(alignments) < 16384:
        raise SystemExit('ARM64 library must support 16KB ELF LOAD alignment')
    with args.library.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    report = dict(abi=args.abi, minimum_api=args.api, sha256=digest,
                  bytes=args.library.stat().st_size, jni_exports_verified=len(contract),
                  strong_imports_verified=len(required), needed=needed,
                  unavailable_imports=unresolved, load_alignments=alignments,
                  actual_android_runtime_tested=False)
    args.output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
