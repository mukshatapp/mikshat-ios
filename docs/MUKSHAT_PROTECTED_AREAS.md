# Mukshat protected-area presentation

This overlay targets `mukshatapp/mikshat-ios` commit
`038ac48ceafb917a8d4491d1c8eb358ad379d056`, using its pinned Kothic submodule
`c5546e4f70128a301fc2f08b391baeafe29e5ee9`. Compile the Android compatibility
profile with `MUKSHAT_LEGACY_SDK_ABI=ON`; its existing solid-area overlay preserves
underlying land-cover on features that are also protected areas.

## Appearance

- Nine classificator types: `leisure-nature_reserve`, `boundary-national_park`,
  `boundary-protected_area`, and protected-area classes 1 through 6.
- Solid fill at 20% opacity: daytime RGB `#7E3FB2`, nighttime RGB `#B388E8`.
- Opaque boundary, 1.5 visual pixels, increasing to 2 at zoom 14.
- Default/outdoors visibility starts at zoom 8; vehicle visibility starts at 10.
  Both continue through the generator's maximum zoom 20.
- Real polygon boundaries, holes and islands are retained; artificial tile cuts
  and internal triangulation diagonals are not outlined.
- This is unrelated to `ShowDownloadedRegions`; it does not enable downloaded
  country shading.

The renderer stores color transparency in the high byte (`255 - alpha`), so a
20% fill is encoded as `0xCC7E3FB2` / `0xCCB388E8`, not alpha `0x33`.

The approved Mukshat daytime sand RGB `#EBA426` is retained only for
`natural-desert` and `natural-beach-sand`. Night RGB/opacity remain those of the
existing application. Sandy beaches retain early visibility from zoom 7. Other
beaches, land-cover, water, labels and unrelated lines are unchanged from the fork.

## Regeneration and checks

Edit MapCSS and run `tools/unix/generate_drules.sh`. Do not hand-edit generated
`drules_*.bin`, classificator, or palette files. Commit generated files separately
from source changes, following the repository instructions.

For a semantic regression check, regenerate an unmodified checkout of the pinned
fork separately, then run:

```sh
python3 tools/python/tests/test_mukshat_protected_styles.py \
  --kothic tools/kothic/src --baseline /path/to/original/data \
  --current data --report /tmp/mukshat-protected-styles.json
```

The local regeneration reproduced the pinned fork's original default binary
byte-for-byte, then passed 7392 checks on modified styles. The check compares
resolved colors and complete rules for unrelated types, rather than palette
indices which can change during regeneration. Classificator and type tables
remain byte-identical to the regenerated fork baseline.

The independent geometry helper tests cover holes, islands, original-edge
clipping, tile seams, winding and large meshes, including sanitizer runs. They
do not establish full engine compilation or GPU rendering. Full Android native
build, OpenGL/Vulkan appearance and device screenshots still require execution
against the final integrated build.
