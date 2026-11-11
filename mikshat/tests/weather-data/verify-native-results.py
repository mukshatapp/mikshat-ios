from pathlib import Path
import json
import re
import sys

log = Path(sys.argv[1]).read_text(errors="replace")
required = ["SearchOnMapManagerTests", "SearchOnMapHeaderViewTests", "SearchTabLayoutRegressionTests",
            "SearchThemeWindowLifecycleTests", "SearchHistoryOnlyTests", "MikshatMemoryDiagnosticsTests",
            "MikshatHeadingCacheLifecycleTests", "MikshatWeatherViewTests"]
started = re.findall(r"Test Case (.*?) started", log)
missing = [name for name in required if not any(name + " " in case for case in started)]
failures = [line for line in log.splitlines() if re.search(r"Test Case .* failed|:\d+: error: -\[", line)]
counts = [(int(a), int(b)) for a, b in re.findall(r"Executed (\d+) tests?, with (\d+) failures?", log)]
passed = len(started) >= 34 and not missing and not failures and any(a >= 34 and b == 0 for a, b in counts)
report = {"casesStarted": len(started), "requiredClasses": required, "missingClasses": missing,
          "executionCounts": counts, "testFailures": failures[-30:], "passed": passed,
          "scope": "Native UIKit and Foundation app tests; not a physical-device or active Metal-map memory profile"}
print(json.dumps(report, ensure_ascii=False))
Path(sys.argv[1]).with_suffix(".summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
if not passed:
    raise SystemExit("Native test execution did not establish all required feature regressions")
