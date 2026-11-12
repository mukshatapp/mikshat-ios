# Search accessory geometry in 4.6.13

The three newly supplied Organic Maps reports identify `com.mikshat.maps`,
4.6.11 (2), iOS 27.0 (24A437). Two are scene-update watchdog terminations
(`0x8BADF00D`, ten seconds); the first is a five-second process-exit watchdog.
Their main threads pass through CoreGraphics path drawing, CoreUI vector-glyph
rasterization, UIImageView geometry and UITableView accessory layout. This is
stronger UI evidence than the earlier logging hypothesis. The app frame at
`0x28DF54` still requires the matching 4.6.11 (2) dSYM for an exact method name.
The reported CoreGraphics/CoreUI region totals are virtual-memory regions,
not measurements of the application's physical RAM.

The separate 20:04:10 JetsamEvent names Apple's `languageassetd` as its victim.
Mikshat is absent from its process list; this record does not establish a new
Mikshat memory-limit termination.

## Source defect and correction

`MikshatDirectionIndicator` was a rotated UIImageView installed directly as a
history cell's accessory. Reconfiguration assigned its frame while the old
rotation could remain active. Setting a transformed view's frame has undefined
geometry, and the accessory and SF Symbol sizing paths shared that view.

The accessory is now an unrotated 28-by-28-point UIView with a fixed intrinsic
size and `sizeThatFits`. Its UIImageView child alone rotates; layout sets the
child's bounds and center, never its transformed frame. Invalid or unavailable
directions clear the child rotation, visibility and accessibility value. Cell
reuse clears the target and removes the accessory. The visible arrow size,
heading and bearing calculation, weak shared refresh timer, bookmark consumer
and location-manager ownership are preserved.

The 4.6.12 logging mutex correction remains included. This change does not add
another GPS owner or alter saved searches, downloads, routing or satellite data.

## Validation and limits

Native regressions in the existing test target cover nonzero rotation,
LTR/RTL attached history-table layout at several widths, repeated layout,
coordinate/text/clear reuse, accessibility, GPS ownership and timer lifetime.
A separate ordinary UIKit scene probe compiles the actual production indicator
and navigation math, with deterministic valid location and heading inputs. It
compares the published 4.6.12 component with this revision on iOS 27.0 and bounds
the old component experiment to avoid unbounded rasterization or memory growth.
See `mikshat/tests/arrow-geometry/README.md` and the arrow-geometry workflow for
commands and raw outcomes. A setup error or a baseline that does not reproduce
is never treated as a reproduced watchdog.

Simulator component coverage does not reproduce the complete physical-device
application or symbolicate the supplied binary. The new build still needs the
user's TestFlight check: first search opening before typing, reopening search,
coordinate-bearing history rows and search from both navigation modes. This
source change does not itself publish a signed IPA or TestFlight build.
