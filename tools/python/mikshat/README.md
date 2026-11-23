Map download validation
=======================

Current source (4.6.17)
-----------------------

Every map, including Saudi Arabia North and South, uses the Organic Maps server
selection and versioned download URLs. The former Google Drive registry and
country-specific diff exclusions have been removed. The meta-server is
`https://meta.omaps.app/maps`; the configured fallback mirrors are Organic Maps
CDNs. A failed or incompatible meta response uses those existing fallback
mirrors without changing the catalog version or app version sent to the server.

The bundled catalog remains `260714`, matching bundled World/WorldCoasts and
existing installed Saudi maps. These official URLs were checked on 2026-11-23:

| Official file | Bytes | Catalog BLAKE3 hash |
| --- | ---: | --- |
| `https://cdn.organicmaps.app/maps/260714/Saudi%20Arabia_North.mwm` | 71760131 | `i5mCFqnSjXOf` |
| `https://cdn.organicmaps.app/maps/260714/Saudi%20Arabia_South.mwm` | 69904708 | `gl/FyL+gwsOW` |

Catalog version, size and hash come from `data/countries.json`; they must not be
copied from a different map release. Future catalog changes use their own
versioned CDN paths rather than a source pinned to `260714`. The app verifies
full-map catalog hashes asynchronously before registration. A diff's final map
is verified after applying the diff, rather than comparing the diff payload to
the full-map hash. Failed validation removes the failed transfer and retains an
older installed map. Production checksum validation remains enabled.

Native regressions
------------------

`storage_tests` exercises the actual downloader, queue and Storage code:

- `MapFilesDownloader_OfficialSources`: both Saudi regions and ordinary maps
  follow all selected mirrors; current/future catalog URLs are versioned and
  escaped; diff URLs and transfer sizes remain supported.
- `StorageDownloadTest_CatalogHashFailurePreservesInstalledMap`: an HTTP-200 HTML
  response fails the ordinary catalog check and preserves an installed Saudi map.
- Existing `StorageDownloadTest_*` regressions cover normal downloading, queued
  validation, cancellation, retry/resume, restored queues and checksum failures.

Run the first two groups with the test runner's filter, for example:

```sh
build/storage_tests --filter='MapFilesDownloader_OfficialSources|StorageDownloadTest_' \
  --data_path="$PWD/data" --user_resource_path="$PWD/data" \
  --writable_path="$PWD/build/storage-test-writable"
```

Some existing download tests need the repository test HTTP server on port 24568.
The former standalone `SaudiSourceTests.cpp` only asserted the retired Drive
registry; it has been replaced by the actual downloader regressions above.

Container inspection
--------------------

`inspect_mwm.py` checks the little-endian section table, section bounds/overlaps,
MWM v11 version/date, geometry header, and (with `--country`) the search/routing
headers and required country sections. It hashes files with SHA-256 in 1 MiB
chunks. It never loads a whole map into RAM and does not make network requests.

After obtaining an official CDN file, run from the repository root:

```sh
python3 tools/python/mikshat/inspect_mwm.py --country --expected-version 260714 --expected-size 71760131 '/path/Saudi Arabia_North.mwm'
python3 tools/python/mikshat/inspect_mwm.py --country --expected-version 260714 --expected-size 69904708 '/path/Saudi Arabia_South.mwm'
python3 -m unittest discover -s tools/python/mikshat -p 'test_*.py'
```

These format/hash checks do not establish successful native rendering, search,
local routing or cross-region routing. Those need native app tests with the
actual Saudi files and matching World/WorldCoasts dependencies.
