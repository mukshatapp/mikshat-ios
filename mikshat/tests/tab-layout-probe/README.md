# Native UIKit tab-layout regression probe

The `diagnostics/search-tab-layout` workflow compiles the repository's actual
`TabView.swift` and `TabViewController.swift` into a small optimized UIKit app,
then runs it on an iPhone 16 simulator with an available iOS 26 runtime. It tests
two source versions without changing their layout behavior:

- 4.6.9 at commit `74b5bf3`, expected to reproduce the alignment failure;
- the current production files, expected to pass.

Two unhosted fixtures match the existing full-app XCTest geometry: two pages with
page 1 selected, resized from 320×480 to 480×320, and the same transition through
a zero-size viewport. Both also run with the actual tab controller attached as
a child of the visible window's root controller. Safe-area insets and window
attachment are recorded; alignment uses the collection's actual viewport width.
The probe requires finite geometry and immediate page alignment, then records
geometry after ten stable layout passes. A separate fresh hosted fixture records
its immediate geometry and again after 100 ms on the main queue, with no explicit
intervening layout or invalidation.

The source fix invalidates flow-layout delegate metrics and attributes through
UIKit's bounds-change hooks. Native matrix run `42933100943` measured the fixed
source passing hosted/unhosted resizing, zero restoration, stable passes and the
next-loop sample. The permanent probe compiles current source as-is; experimental
source transformations have been removed.

Original and compiled files, SHA-256 manifests, native geometry and failure logs
are uploaded as artifacts. Full launch logs are also printed in GitHub job logs.
Optional `--trace-layout` adds bounded logging at parent layout entry, after
`super`, before comparing content bounds, and in the size delegate. It also
records stored/active layout identities, active class and estimated item sizes.
The manifest records the exact instrumented hash and logging stages.

Only fonts, colors, separator construction, label font scaling and the app's base
controller dependency are stubbed. UIKit collections, Auto Layout, production
tab code and optimized Swift execution are real. The probe does not build the
map engine or load user data. It verifies this geometry regression; it does not
reproduce the reported search freeze by itself or cover GPS, keyboard, map data
or physical-device memory.

Run preparation checks locally:

```sh
python3 -m unittest discover -s mikshat/tests/tab-layout-probe -p 'test_*.py' -v
```
