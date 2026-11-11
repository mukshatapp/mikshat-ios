#include "libs/storage/saudi_map_download_source.hpp"

#include <cassert>
#include <string>

int main()
{
  using namespace storage;
  assert(kSaudiMapDataVersion == 260714);
  auto const * north = FindSaudiMapDownloadSource("Saudi Arabia_North");
  auto const * south = FindSaudiMapDownloadSource("Saudi Arabia_South");
  assert(north && south && north != south);
  assert(north->m_size == 71760131 && south->m_size == 69904708);
  assert(north->m_hash == "i5mCFqnSjXOf" && south->m_hash == "gl/FyL+gwsOW");
  assert(north->GetUrl() == "https://drive.usercontent.google.com/download?id=1a7BwcYn1SsV1gPIvdvyfNN95E97hoV5R&export=download&confirm=t");
  assert(south->GetUrl() == "https://drive.usercontent.google.com/download?id=1oGhGU__h1XZzBMTZfJnnnv5r-ftJE6kk&export=download&confirm=t");
  for (auto const * other : {"World", "WorldCoasts", "Saudi Arabia", "Saudi Arabia_North.mwm", "France"})
    assert(!FindSaudiMapDownloadSource(other));
}
