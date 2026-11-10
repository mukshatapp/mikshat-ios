# Isolated UIKit theme-hook probe

This probe runs real UIKit attachment and keyboard-focus cycles using the
repository's actual `didMoveToWindow` hook bodies and `SwizzleStyle.m`. It avoids
the full map/CoreApi build. Theme rendering and the Maps app delegate are minimal
stubs, so this isolates dispatch behavior rather than reproducing the entire
search screen.

On macOS with Xcode and an already booted iPhone simulator:

```bash
bash mikshat/tests/search-theme-probe/run_probe.sh \
  "$PWD" /tmp/mikshat-theme-fixed SIMULATOR_UDID fixed
```

Pass another checkout (or a directory containing the original theme files) as
`SOURCE_ROOT` to test an earlier revision. The source preparer preserves the
original Swift hook declarations, including `override`; it does not substitute
hand-written equivalent hooks. A baseline run can pass, crash, or time out. A
passing baseline must be reported as a failure to reproduce that UIKit failure,
not counted as evidence that the device report is resolved.

Each build records `generated/source-manifest.json`, compiler logs, `launch.log`
and `probe-outcome.json`. The app must write a successful completion report after
20 attach/focus/detach cycles for the launcher to pass. Exit without a report or a
120-second timeout fails. A distinct-selector build additionally exercises a
second installation to verify the one-time hook installer remains active.

The probe uninstalls its own test app before each run, preventing a previous
completion report from being mistaken for the current run's result. It does not
install or launch the real Mikshat app. Use full-app XCTest and a physical iPhone
crash report for end-to-end confirmation.

Extraction tests can run without Xcode:

```bash
python3 -m unittest discover -s mikshat/tests/search-theme-probe -p 'test_*.py' -v
```
