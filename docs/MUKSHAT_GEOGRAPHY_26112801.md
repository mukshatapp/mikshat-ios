# Mukshat geographic presentation

The preserved Android SDK uses native styles generated from the same source as
the engine. The map catalog and classifier stay at261110; the four supplemental
map files are not rewritten.

## Style policy

`data/styles/mukshat/Geography.mapcss` is imported last by default, outdoors and
vehicle families in light and dark themes. Geographic detail starts at draw9,
reserves start at8 and remain visible at closer scales.

The Android ruler starts with a60dp minimum and rounds the real ground distance
up to the next preferred unit. At Saudi latitudes, nominal integer draw8/9/10
corresponds to50/20/10km. Density cancels from the ruler/draw-scale equation.
Fractional pinch zoom and latitude mean an integer rule can transition slightly
before or after the rounded ruler text changes. These are not zoom20 or zoom50.

Country map minimum loading is8 in the legacy branch so reserve geometry is
available at the50km reference. The earlier single-rectangle read-detail+4
policy remains unchanged. The modern SDK keeps its original loading policy.

Reserve fills use opacity20% at8,12% at9 and4% at10 or closer. Their BG-top
priority is1: above size-sorted sand/landcover, below waterways and foreground
geometry. Borders use a0.01 depth increment so they stay below waterways too.
They retain the original uncut-triangle boundary extraction, holes and islands.

Colors:

| Role | Day | Night |
| --- | --- | --- |
| Reserve names/borders | `#7E3FB2` | `#B388E8` |
| Unpaved road geometry/names | `#6B3F20` | `#A9754F` |
| Watercourse geometry/names | `#006AB5` | `#64B5F6` |
| Depression/meadow names | `#246B38` | `#81C784` |

Watercourse and track strokes are continuous, including intermittent rivers and
streams. Original geometry widths are retained with a1px fallback for newly
visible styles. Underground waterways remain hidden. Other unpaved highways
carry separate `psurface` types, so the legacy feature renderer recognizes those
types and applies the same brown continuous stroke without changing map data.

## Names and typography

Many supplemental geographic names use `place-locality`, not dedicated types.
The native helper recognizes complete Arabic first words such as `فيضة`,
`روضة`, `خباري`, `قاع`, `وادي` and `شعيب`. It is gated to generic landform types;
city/village/hamlet and POI-only types keep their existing colors. It checks
default and Arabic names, so an English default name does not mask the Arabic
geographic classification. Reserve and unpaved-road types take precedence.

`CaptionDefToFontDecl` enlarges point/area captions and path text by20% only for
the preserved legacy SDK. Layout and collision bounds use the actual enlarged
font. Modern SDK typography remains unchanged. Tajawal loading and fallback are
provided by the companion font overlay.

## Verification

- `tools/mukshat/test_geographic_presentation.sh`:43 name/presentation checks,
  also run under ASAN/UBSAN.
- `tools/mukshat/detail_policy_test.py`:34 compiled checks against actual source
  fragments for modern and legacy policies.
- Existing reserve geometry suite:35 checks/13 scenarios, unchanged extraction.
- `tools/python/tests/test_mukshat_geographic_styles.py`:15174 checks against
  generated family binaries and the previous37315b5 baseline. Existing unrelated
  type rules and named colors remain unchanged; classifier/catalog bytes match.
- Companion font overlay: actual FreeType/HarfBuzz shaping and ruler math tests.

Run `tools/unix/generate_drules.sh` after editing MapCSS. Keep generated drules
and side files in a separate commit. Actual Android rendering and native engine
build verification are coordinated by the release task; host checks alone do
not establish GPU or device behavior.
