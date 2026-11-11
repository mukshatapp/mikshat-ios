from collections import Counter, defaultdict
from pathlib import Path
import json
import re
import sys


EXPECTED_CLASSES = {
    "SearchOnMapManagerTests": 5,
    "SearchOnMapHeaderViewTests": 5,
    "SearchTabLayoutRegressionTests": 3,
    "SearchThemeWindowLifecycleTests": 4,
    "SearchHistoryOnlyTests": 7,
    "MikshatMemoryDiagnosticsTests": 2,
    "MikshatHeadingCacheLifecycleTests": 2,
    "MikshatWeatherViewTests": 6,
}
CASE_EVENT = re.compile(
    r"\bTest Case\s+(['\"])(.*?)\1\s+(started|passed|failed|skipped|cancelled|canceled)\b", re.IGNORECASE
)
SUMMARY = re.compile(
    r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", re.IGNORECASE
)
BLOCKED = re.compile(
    r"Test Case .* (?:failed|skipped|cancelled|canceled)\b|"
    r":\d+(?::\d+)?: error: -\[|Test Suite .* failed\b|"
    r"\*\* TEST (?:FAILED|CANCELLED|CANCELED)\b|"
    r"\b(?:Testing|Test (?:run|session))\b.*\b(?:cancelled|canceled)\b|"
    r"Restarting after unexpected exit|Test runner .*\bcrashed\b", re.IGNORECASE
)


def case_identity(identifier):
    # XCTest normally prints -[Module.Class method]; accept its dotted Swift spelling too.
    match = re.fullmatch(r"-?\[([^\s]+)\s+([^\s\]]+)\]", identifier)
    if not match:
        match = re.fullmatch(r"([\w.]+)[./](test[^()\s]+)(?:\(\))?", identifier)
    if not match:
        return None
    return match[1].rsplit(".", 1)[-1], match[2]


def analyze(log):
    log = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", log)
    outcomes = defaultdict(Counter)
    unrecognized = []
    for event in CASE_EVENT.finditer(log):
        identity = case_identity(event[2])
        if identity is None:
            unrecognized.append(event[2])
        else:
            outcomes[identity][event[3].lower()] += 1
    counts = [dict(executed=int(a), skipped=int(b or 0), failures=int(c))
              for a, b, c in SUMMARY.findall(log)]
    failures = [line for line in log.splitlines() if BLOCKED.search(line)]
    class_counts = {}
    for name, expected in EXPECTED_CLASSES.items():
        cases = [events for (class_name, _), events in outcomes.items() if class_name == name]
        class_counts[name] = dict(expected=expected, uniqueCases=len(cases),
                                  started=sum(case["started"] for case in cases),
                                  passed=sum(case["passed"] for case in cases))
    incomplete = [f"{name}.{method}" for (name, method), events in outcomes.items()
                  if events != Counter(started=1, passed=1)]
    unexpected = sorted({name for name, _ in outcomes} - EXPECTED_CLASSES.keys())
    expected_total = sum(EXPECTED_CLASSES.values())
    succeeded = "** TEST SUCCEEDED **" in log
    passed = (succeeded and not failures and not unrecognized and not incomplete and not unexpected
              and all(values["uniqueCases"] == values["started"] == values["passed"] == values["expected"]
                      for values in class_counts.values())
              and all(count["failures"] == count["skipped"] == 0 for count in counts)
              and any(count["executed"] == expected_total for count in counts))
    return {"casesStarted": sum(case["started"] for case in outcomes.values()),
            "expectedTotal": expected_total, "classCounts": class_counts,
            "executionCounts": counts, "testFailures": failures[-30:],
            "incompleteOrRepeatedCases": sorted(incomplete), "unexpectedClasses": unexpected,
            "unrecognizedCases": unrecognized, "xcodebuildSucceeded": succeeded, "passed": passed,
            "scope": "Native UIKit and Foundation app tests; not a physical-device or active Metal-map memory profile"}


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: verify-native-results.py XCODEBUILD_LOG")
    path = Path(sys.argv[1])
    report = analyze(path.read_text(errors="replace"))
    print(json.dumps(report, ensure_ascii=False))
    path.with_suffix(".summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if not report["passed"]:
        raise SystemExit("Native test execution did not establish every required case passing without skips or cancellation")


if __name__ == "__main__":
    main()
