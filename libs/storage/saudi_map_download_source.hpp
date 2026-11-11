#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace storage
{
// These Drive files belong to the bundled 260714 catalog. A later catalog must
// explicitly update this manifest; never install these bytes under a newer version.
inline constexpr int64_t kSaudiMapDataVersion = 260714;

struct SaudiMapDownloadSource
{
  std::string_view m_countryId;
  std::string_view m_driveFileId;
  uint64_t m_size;
  std::string_view m_hash;

  std::string GetUrl() const
  {
    // Public download endpoint. NSURLSession/HttpClient follow its HTTPS redirects.
    // confirm=t avoids the large-file confirmation page where Drive supports it;
    // any HTML/permission/quota response still fails the pinned size/hash validation.
    return "https://drive.usercontent.google.com/download?id=" + std::string(m_driveFileId) +
           "&export=download&confirm=t";
  }
};

inline constexpr std::array<SaudiMapDownloadSource, 2> kSaudiMapDownloadSources = {{
    {"Saudi Arabia_North", "1a7BwcYn1SsV1gPIvdvyfNN95E97hoV5R", 71760131, "i5mCFqnSjXOf"},
    {"Saudi Arabia_South", "1oGhGU__h1XZzBMTZfJnnnv5r-ftJE6kk", 69904708, "gl/FyL+gwsOW"},
}};

inline SaudiMapDownloadSource const * FindSaudiMapDownloadSource(std::string_view countryId)
{
  for (auto const & source : kSaudiMapDownloadSources)
    if (source.m_countryId == countryId)
      return &source;
  return nullptr;
}
}  // namespace storage
