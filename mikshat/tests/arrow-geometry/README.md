# Actual UIKit direction accessory geometry probe

This isolated iOS 27 app compiles the **verbatim production**
`MikshatDirectionIndicator` class and complete `MikshatNavigationMath.swift`.
It uses the original `location.north.fill` SF Symbol and UIKit/CoreUI, a normal
foreground `UIWindowScene`, real `UITableView` accessories, and real dequeue/reuse.
Only color, localization and location/heading acquisition are fixture dependencies.
The location is over 200 m from the target, with 2 m accuracy; 48 LTR/RTL cases
exercise nonzero 15–150° angles through the real `target` setter. It never calls
a replacement rotation algorithm or changes the extracted production class.

On an Apple Silicon Mac with Xcode 27 and a booted iPhone iOS 27 simulator:

```bash
bash mikshat/tests/arrow-geometry/run_probe.sh \
  /path/to/source /tmp/arrow-fixed SIMULATOR_UDID fixed
```

Run **separate apps/processes** for baseline and fixed. For the baseline, supply
a source directory containing the two original files at their repository paths
from pinned commit `59b8e1b752092f07ada180cefaf1d23596f03559`. For fixed, supply
the current checkout. No installed desktop Simulator.app is required; the app
itself must prove foreground scene, key window and active application readiness.
The script builds optimized Swift, signs the disposable probe, installs, launches,
collects evidence, prints the strict outcome, then terminates only its probe app.

Outputs include `generated/source-manifest.json` (source/class SHA-256 and exact
compile settings), `compile.log`, `launch.log`, `geometry-trace.jsonl`,
`probe-outcome.json`, and an optional screenshot. The trace records outer/child
frames, bounds, transform matrices, actual nonzero child angle, target, visibility,
accessibility label/value, real reuse count and measured process footprint.
`prepare_probe.py SOURCE_ROOT OUTPUT_DIR --variant baseline|fixed` can be used
separately if a caller owns compilation and launch.

The baseline monitor starts before injecting the nonzero location. It stops a
specific started layout case on dimensions over 84 pt, a three-second case stall,
or footprint growth over 160 MiB (512 MiB absolute ceiling). The background
monitor reads locked metadata and process memory, never UIKit. It writes a durable
case marker before layout and a result before exiting on a guard. The host also
has a 50-second result deadline. These safeguards reduce runaway raster allocation;
they are not an allocation sandbox and cannot make each individual allocation
bounded. Setup failures, inactive scenes and missing reports are failures, never
reproductions. A passing baseline is explicitly **not reproduced**. The fixed
variant must finish all 48 cases with an unrotated 28×28 pt outer container and
28×28 pt symbol bounds, correct heading rotation, unchanged target and accessibility.

Exit 0 means either fixed invariants passed or a baseline run produced valid
`reproduced`/`not-reproduced` evidence. Every other result fails. The JSON outcome
must be reported alongside the exit status; baseline success alone proves nothing
about the original device report. This probe does not cover physical GPS, an
active map, the complete search screen, or full-app end-to-end behavior.

Extraction and evidence-classification checks (no Xcode needed):

```bash
python3 -m unittest discover -s mikshat/tests/arrow-geometry -p 'test_*.py' -v
```
