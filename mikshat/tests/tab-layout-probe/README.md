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

Both transitions also run as separate hosted fixtures: the actual tab controller
is attached as a child of the visible window's root controller, and its view is
resized without forcing a hardware orientation change. Reports include window
attachment and safe-area insets. Alignment always uses the collection's actual
viewport width, rather than an assumed full-screen width.

The diagnostic run also records geometry after the ten forced stable passes.
A fifth fresh hosted fixture records geometry immediately after resizing, then
again after 100 ms on the main queue, without any intervening explicit layout or
invalidation. These extra samples do not replace the original immediate geometry
assertions. They distinguish transient deferred UIKit layout from a persistent
alignment problem.

The 4.6.9 source at commit `74b5bf3` is expected to fail the page-alignment
assertions. An initial `guarded` candidate moved collection `layoutIfNeeded()` inside the
positive-size/not-dragging/valid-item guard, but the native iOS 26.5 probe still
reported the same failure: a 480-point viewport retained a 640-point total content
width from two old 320-point items. Preparing layout alone did not invalidate
cached delegate sizes. The first `metrics` run also failed identically. Current
runs therefore expect that known failure while collecting timing evidence;
they do not designate either candidate as a validated production fix.

The `metrics` candidate explicitly invalidates flow-layout delegate metrics and
attributes, then prepares layout inside that guard before `scrollToItem`. The production working copy is not
modified. Optional `--trace-layout` instruments the temporary compiled source at
parent layout entry, after `super`, before comparing content bounds, and in the
size delegate. Its exact source hash and instrumentation stages are recorded.
Generated original/compiled files, SHA-256 manifests and native output
are uploaded as artifacts. Each native outcome must match the explicitly
declared expectation; the current trace run expects the already measured
alignment failure for both sources while gathering diagnostic evidence.

A third experimental `bounds-notify` candidate uses the metrics candidate plus a
private content-collection subclass. Its `bounds` observer schedules parent
layout only when the viewport size changes, through a weak closure; it does not
schedule parent layout for scrolling. This tests whether the parent had observed
old child bounds before Auto Layout committed the new size. Its expected result
is a pass with the same immediate assertions, without asynchronous realignment.
This transformation applies only to the compiled probe copy until native results
support a production change.

The trace run disproved the old-child-bounds hypothesis: after `super` the parent
already observes the new viewport size, yet delegate sizes stay cached. Two new
experimental variants test separate mechanisms: `needs-layout` explicitly marks
the collection view dirty before guarded `layoutIfNeeded`; `bounds-layout` uses
a private flow-layout subclass to invalidate delegate metrics/attributes through
UIKit's own bounds-change invalidation hooks. Its stored property retains the
base `UICollectionViewFlowLayout` type. Trace records stored/active layout object
identities, active class and estimated item sizes. Full native trace logs are also
printed in GitHub job logs so they require no artifact download.

Only fonts, colors, separator construction, label font scaling and the app's
base view-controller dependency are stubbed. UIKit collections, Auto Layout,
production tab layout and controller code, and optimized Swift execution are
real. This is a geometry regression probe; it does not reproduce the user's
search freeze by itself or test GPS, theming, keyboard, map data, or device memory.

Run preparation checks locally:

```sh
python3 -m unittest discover -s mikshat/tests/tab-layout-probe -p 'test_*.py' -v
```
