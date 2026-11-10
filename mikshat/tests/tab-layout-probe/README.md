# Native UIKit tab-layout probe

The `diagnostics/search-tab-layout` workflow compiles the repository's **actual**
`TabView.swift` and `TabViewController.swift` into a small optimized UIKit app and
runs it on an iPhone 16 simulator with an available iOS 26 runtime. It does not
build the map engine or load map/user data.

Two unhosted geometry fixtures match the existing full-app XCTest behavior:

- two pages, page 1 selected: 320×480 → 480×320;
- two pages, page 1 selected: 320×480 → zero → 480×320.

The app records native bounds, content size, offsets, page position and item
metrics after each transition. It requires finite geometry and restored page
alignment. It also exercises ten unchanged layout passes per fixture.

The 4.6.9 source at commit `74b5bf3` is expected to fail the page-alignment
assertions. The candidate uses an explicit, recorded transformation moving
collection `layoutIfNeeded()` **inside** the positive-size/not-dragging/valid-item
guard immediately before `scrollToItem`. The production working copy is not
modified. Generated original/compiled files, SHA-256 manifests and native output
are uploaded as artifacts. A baseline unexpected pass or candidate failure fails
the workflow.

Only fonts, colors, separator construction, label font scaling and the app's
base view-controller dependency are stubbed. UIKit collections, Auto Layout,
production tab layout and controller code, and optimized Swift execution are
real. This is a geometry regression probe; it does not reproduce the user's
search freeze by itself or test GPS, theming, keyboard, map data, or device memory.

Run preparation checks locally:

```sh
python3 -m unittest discover -s mikshat/tests/tab-layout-probe -p 'test_*.py' -v
```
