# Mukshat 5.4 map presentation

The preserved Android consumer receives a legacy-only detail policy. The reader
uses the same screen-centred 60 × visual-scale pixel probe and Earth-distance
calculation as the visible ruler. Because that ruler rounds strictly upward,
raw distances below 5000 m show existing brown roads and distances below 2000 m
show intermittent streams and above-ground power lines. Density, fractional
zoom, camera projection and centre latitude therefore use the actual projection
rather than a nominal integer zoom. A bucket transition cancels prior reads and
advances the existing generation before new immutable EngineContext snapshots
are queued. Modern SDK behaviour remains unchanged.

Matching drawing rules are available from draw scale 9 in default, outdoors and
vehicle, day and night. Runtime filtering determines the requested thresholds.
Underground water and power exclusions remain intact. Map features still need
to be present in the downloaded MWM and its spatial index; no missing source
data is invented.

Arabic unnamed captions use existing translated type keys after preferred real
names have been selected. Primary and auxiliary names always win, including
non-Arabic proper names. Intermittent stream, current brown-road and scrub
fallbacks use respectively `waterway-stream-intermittent`, `highway-track` and
`natural-scrub`. The reconstructed Android consumer generates their Arabic
values from `tooling/map-details-26112802/localized-type-overrides.json`:
مسيل / طريق ترابي / فيضة. Native source map names and classification are unchanged.

Caption size changes from 1.2 to 1.38; shield text receives its own 1.15 factor,
so both grow by an additional 15% relative to the preceding release. Ruler and
other map-control text sizes stay independent. The exact existing Tajawal font
and reserve/road/water colour and layer policies are retained.

Host checks:

```sh
python3 tools/mukshat/test_detail_visibility.py
g++ -std=c++23 -Wall -Wextra -Werror -I libs tools/mukshat/caption_fallback_test.cpp -o /tmp/caption-test
/tmp/caption-test
bash tools/mukshat/test_geographic_presentation.sh
```

Drawing rules are regenerated through `tools/unix/generate_drules.sh` and verified
against the preceding release with `tools/python/tests/test_mukshat_map_details.py`.
These checks do not claim physical-device rendering or sensor accuracy.
