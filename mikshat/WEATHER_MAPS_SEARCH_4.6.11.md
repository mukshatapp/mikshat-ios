# Mikshat 4.6.11: Saudi maps, selected-location weather and search

## Result

- Saudi North/South use the supplied public Google Drive source through the existing download UI. Map files are not bundled in the IPA. World/WorldCoasts and other regions retain their existing source.
- Search opens history directly. Categories and its pager are removed; old category-index preferences migrate to history. Coordinate entry and saved direction targets remain available.
- The selected-place sheet ends at its content instead of reserving a blank screen. A weather action follows the existing DD/DDM rows; it uses that place's immutable coordinates and name.
- Weather uses the requested free, keyless Open-Meteo endpoint in Debug and Release. Current conditions, wind coming from its source, and the first twelve strictly future hourly slots use the selected location's timezone and each slot's own day/night metadata.
- Weather has a bounded per-site atomic cache, offline/aged states, request limits, retry delays, timeouts, streaming response limits, and visible-screen lifecycle guards. It does not request GPS or install a background service.
- Search memory diagnostics record process footprint, resident memory and available headroom through the existing logger. Passive heading reads no longer construct a location manager when no compass client is active.

## Data and resource boundaries

The supplied Drive files were downloaded anonymously and inspected on 2026-11-11. Both match catalog version 260714, the exact byte sizes and truncated BLAKE3 hashes in `libs/storage/saudi_map_download_source.hpp`. Their timestamps match bundled World/WorldCoasts. See `tools/python/mikshat/README.md` for fingerprints and inspection limits. Drive HTML/quota errors, size/hash failures and wrong catalog versions must fail through the existing UI; an installed map must remain usable. No Saudi diff download or silent CDN fallback is configured.

Weather defaults: 20 sites, 2 MiB encoded cache, 15-minute freshness, 512 KiB maximum streamed response, four concurrent site requests, 20-second request timeout and 25-second resource timeout. Refresh failure preserves the last valid response. Cached past hours are removed from presentation; remaining future hours are counted explicitly. Shared requests may finish after a screen closes, but closed/stale screens ignore results.

Open-Meteo data attribution is displayed in the screen. The service's free-access terms are separate from its CC BY 4.0 data licence: the free endpoint is described as non-commercial, limited to 600 requests/minute, 5,000/hour and 10,000/day, without an uptime guarantee. Apps with advertising/subscriptions require the appropriate service arrangement. The user's choice of the free endpoint does not itself establish commercial permission. No credentials are stored in the app.

Official references checked on 2026-11-11:

- https://open-meteo.com/en/docs
- https://open-meteo.com/en/terms
- https://open-meteo.com/en/pricing
- https://creativecommons.org/licenses/by/4.0/

## Verification

The feature workflow `.github/workflows/mikshat-maps-weather.yml` runs the production Foundation weather source against deterministic fixtures, map-container regressions, the actual Saudi source registry, and native iOS feature tests. It records actual Xcode/runtime versions and requests iPhone 16 with an available iOS 26 runtime. A separate single live Open-Meteo request uses a public Riyadh reference point; service failure is reported separately from deterministic tests.

Native weather images use synthetic injected data rendered by real UIKit views at portrait/landscape viewports, including light/dark and large text. They do not establish physical rotation, active Metal-map navigation, real-device memory or a live forecast screenshot. The simulator ZIP is not a signed iPhone IPA.

The available Linux checks pass nine container tests, standalone source-registry assertions and diff formatting. Native/Swift execution results must be read from the feature workflow before promoting this source.

The supplied Jetsam report records per-process-limit termination around 2,098 MiB for Organic Maps, without a matching application version, stack or search state. The user reports the problem with satellites disabled. Removing an avoidable heading-manager allocation and adding phase measurements does not establish that the physical-device search termination is fixed. Confirm on both affected devices with satellites off, collect matching diagnostics, and profile the active map/search process before claiming that issue resolved.

No application identifiers, signing identities, activation data, bookmark files or saved maps are intentionally changed by this feature. Publishing a signed release remains a separate step.
