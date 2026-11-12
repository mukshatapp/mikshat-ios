#!/usr/bin/env bash
set -euo pipefail

task_repo=$(cd "$(dirname "$0")/../../.." && pwd)
task_output=${MIKSHAT_LOG_TEST_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/mikshat-log-test.XXXXXX")}
task_baseline_ref=
if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || $1 != --baseline-ref ]]; then
    echo "Usage: $0 [--baseline-ref COMMIT]" >&2
    exit 2
  fi
  task_baseline_ref=$(git -C "$task_repo" rev-parse --verify "$2^{commit}")
fi
mkdir -p "$task_output"
task_output=$(cd "$task_output" && pwd)

task_link_flags=(-Wl,--gc-sections)
if [[ $(uname -s) == Darwin ]]; then
  task_link_flags=(-Wl,-dead_strip)
fi

build_source() {
  "${CXX:-c++}" -std=c++23 -DRELEASE -g -O1 -fno-omit-frame-pointer \
    -fsanitize=thread -ffunction-sections -fdata-sections -pthread \
    -I"$1/libs" "$1/libs/base/logging.cpp" "$1/libs/base/thread.cpp" \
    "$task_repo/mikshat/tests/logging/LogHelperConcurrencyTests.cpp" \
    "${task_link_flags[@]}" -o "$2"
}

if [[ -n $task_baseline_ref ]]; then
  mkdir -p "$task_output/baseline-source"
  git -C "$task_repo" archive "$task_baseline_ref" libs/base libs/std \
    | tar -x -C "$task_output/baseline-source"
  build_source "$task_output/baseline-source" "$task_output/baseline-tsan"
fi
build_source "$task_repo" "$task_output/current-tsan"

python3 - "$task_output" "$task_baseline_ref" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys

directory, baseline_ref = Path(sys.argv[1]), sys.argv[2]
environment = dict(os.environ, TSAN_OPTIONS='halt_on_error=1:exitcode=66')
summary = {'baselineRef': baseline_ref or None, 'threads': 32,
           'callsPerThread': 1000, 'productionSources': True, 'runs': []}

def run(name, arguments, expect_race=False):
    log_path = directory / (name + '.log')
    with log_path.open('w') as log:
        process = subprocess.run(arguments, stdout=log, stderr=subprocess.STDOUT,
                                 env=environment, timeout=60)
    text = log_path.read_text()
    race = ('ThreadSanitizer: data race' in text and
            'LogHelper::GetThreadID' in text and 'LogHelper::WriteProlog' in text)
    passed = (process.returncode == 66 and race) if expect_race else (
        process.returncode == 0 and 'PASS: 32000 actual production WriteProlog calls' in text and
        'ThreadSanitizer:' not in text)
    result = {'name': name, 'exitCode': process.returncode,
              'expectedRace': expect_race, 'helperRaceReported': race, 'passed': passed}
    summary['runs'].append(result)
    print(json.dumps(result))
    if not passed:
        print(text[-12000:])
        raise SystemExit('No successful regression verdict; inspect ' + str(log_path))
    if expect_race:
        print('Baseline ThreadSanitizer confirms the production GetThreadID/WriteProlog race.')
    else:
        print(text.strip())

if baseline_ref:
    run('baseline-race', [str(directory / 'baseline-tsan')], expect_race=True)
    run('baseline-serialized-control',
        [str(directory / 'baseline-tsan'), '--serialize-control'])
run('current-unserialized', [str(directory / 'current-tsan')])
summary['passed'] = True
(directory / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print('PASS: production-source logging regression; evidence in ' + str(directory))
PY
