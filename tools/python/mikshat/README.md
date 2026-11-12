Saudi map download validation
============================

`inspect_mwm.py` checks the little-endian section table, section bounds/overlaps,
MWM v11 version/date, geometry header, and (with `--country`) the search/routing
headers and required country sections. It hashes files with SHA-256 in 1 MiB
chunks. It never loads a whole map into RAM and does not make network requests.

Run from the repository root after obtaining the public Drive downloads:

```sh
python3 tools/python/mikshat/inspect_mwm.py --country --expected-version 260714 --expected-size 71760131 '/workspace/mikshat-weather-maps-inspection/Saudi Arabia_North.mwm'
python3 tools/python/mikshat/inspect_mwm.py --country --expected-version 260714 --expected-size 69904708 '/workspace/mikshat-weather-maps-inspection/Saudi Arabia_South.mwm'
python3 -m unittest discover -s tools/python/mikshat -p 'test_*.py'
```

The downloaded files inspected on 2026-11-11 passed these checks:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| Saudi Arabia_North.mwm | 71760131 | `6cd35fcb5b2bcd8c0ce5f9249426126c1a3c56635033c07fde855b9316651fe0` |
| Saudi Arabia_South.mwm | 69904708 | `7591a4c97628994b04856b84988ea6259bda4bf4c194702ef39817f02d484425` |

Both have MWM format v11, Country map headers, data version `260714`, search
header v2, routing header v0, and cross-MWM header v2. Their version timestamp
`1783989722` equals the bundled World and WorldCoasts timestamp. This is a
bounded format check, not evidence that native map/search/routing tests passed.

The actual file BLAKE3 hashes also match the pinned catalog exactly:
North `i5mCFqnSjXOf`, South `gl/FyL+gwsOW` (first nine digest bytes, base64).
This offline check used a temporary scalar verifier that first passed all eight
repository known-answer vectors and the standard `abc` vector. The app keeps
using its existing `coding::Blake3` implementation.

SHA-256 here is an inspection fingerprint, not the catalog's truncated BLAKE3
integrity hash. The app checks the catalog hash before registering the map.
The country ID is established by the download mapping and catalog name; this
helper does not infer geographic identity from arbitrary binary contents.
Header/section checks do not prove map rendering, offline search, local routes,
cross-region routes, or compatibility with World/WorldCoasts. Those need native
app checks using both Saudi maps and the app's World/WorldCoasts dependencies.

When updating the source, inspect both replacement files first. Update the
public Drive file IDs together with the exact matching catalog data version,
byte sizes, and catalog BLAKE3 hashes in `saudi_map_download_source.hpp`.
Keep World and WorldCoasts on their existing download/bundle path. Test normal
download progress, cancellation, retry/resume, restart restoration, and update
over an existing map. A Drive HTML confirmation, quota page, HTTP error, wrong
size, or wrong hash must fail through the existing download UI and leave the
installed map available. The source provides full `.mwm` files only; it must
never be used to request `.mwmdiff` files.
