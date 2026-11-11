# Weather data regression runner

Run on a machine with the Swift toolchain (for example the existing macOS CI runner):

```sh
./mikshat/tests/weather-data/run.sh
```

The runner compiles the production Foundation-only source without the app or map engine, then runs deterministic synthetic tests. It does not contact Open-Meteo. `fixtures/riyadh-synthetic.json` is explicitly synthetic, with the documented Open-Meteo schema, Unix seconds, 72 consecutive hourly slots, nullable readings, WMO codes, and per-slot day/night metadata. Neither this fixture nor this runner proves a live network response or an iOS app build.

Coverage includes selected-coordinate request parameters, current/first twelve strictly future hours, retaining nullable slots, unit and parallel-array rejection, malformed/oversized JSON, all 28 documented WMO codes, missing and unknown conditions, per-slot day/night, eight meteorological source directions, calm/missing/invalid wind, midnight in Riyadh, repeated local times across Berlin DST, raw metadata round trips, cache freshness, offline retention, per-location isolation and tolerance, disk reload/corruption, LRU count/byte bounds, and shared request deduplication/invalid-response validation, concurrent request limits, and provider-wide retry deadlines.

The managed Linux workspace has no `swift`, `swiftc`, or Xcode, so the Swift runner and native iOS build must be executed by macOS CI before release. `bash -n` and fixture/schema checks can run here.

## Contract for the UIKit screen

`MikshatWeatherRepository` is an actor. Await `cached(for:)` first, render its original `fetchedAt` with a saved/aged state, then call `refresh(for:force:)`. A regular refresh reuses a fresh matching snapshot; a manual refresh bypasses freshness, while all refreshes respect request deduplication, concurrency bounds and retry deadlines. A failure leaves the last valid in-memory and disk response intact. The screen owns its selected place name, its main-actor UI updates, its visible-only connectivity observer, and its task identity/cancellation check. Shared in-flight requests can finish after a screen closes; the screen must ignore those results. No permanent background service exists.

Snapshots expose `futureHours(at:limit:)`; this retains the first 12 consecutive source slots strictly later than the supplied absolute time, including slots with missing readings. An older cache can therefore return fewer than 12 (or zero) future slots; the screen must show this explicitly. The core does not call cached current weather fresh. `isFresh(at:)` uses 15 minutes by default; a repository can inject a different freshness duration for testing.

`MikshatWeatherCondition` returns localization keys and lightweight local SF Symbol names; the app resolves the keys through its localization system and supplies its generic SF Symbol fallback if necessary. `MikshatWeatherWind.bearingDegrees` points toward the wind's source (coming FROM) and is independent of map/device rotation. Speed below 0.5 km/h is calm; missing/invalid speed or direction has no source arrow.

## Storage and resource policy

- A separate `Caches/MikshatWeather/weather-v1.json` file stores raw validated request coordinates, fetched dates, original current/hourly Unix-derived absolute dates, WMO codes, `is_day`, and the site's IANA timezone. Map and bookmark data are not read or changed.
- Keys round latitude/longitude to four decimal places (about 11.1 m north/south). Every cache match, including a neighboring key, is checked with a haversine distance no greater than 25 m from the ORIGINAL request coordinate. Invalid coordinates are rejected. Requests always use the actual selected coordinates, without this key rounding.
- Defaults are 20 least-recently-used sites and 2 MiB total encoded cache. Writes are atomic. A failed refresh or disk write leaves the preceding disk file intact. Corrupt/incompatible/oversized weather files are ignored.
- Responses stop at 512 KiB while streaming, with a 20 s request timeout and 25 s resource timeout. Declared oversized responses are rejected before body acceptance. Redirects remain on HTTPS `api.open-meteo.com`; normal system HTTPS validation remains enabled. Default bounds also allow at most four simultaneous site requests and bounded retry metadata.
- Retry-After accepts seconds or an HTTP date and applies the provider deadline across sites. HTTP 429 without a valid header defaults to a 60 s pause. Other failures enforce at least 30 s per-site delay. Closing a screen does not cancel a request shared with another consumer, and late results must be ignored by the screen.
- Network requests, JSON parsing and disk I/O occur outside the main actor; the UIKit screen must apply results on the main actor.

The only configured endpoint is the explicitly requested free public endpoint `https://api.open-meteo.com/v1/forecast`, with no key, account or paid subscription. This source file does not claim commercial-distribution permission. Current terms/licensing and live API checks are recorded separately by the delivery report.
