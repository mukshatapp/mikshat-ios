#pragma once

#include "indexer/feature.hpp"
#include "indexer/ftypes_matcher.hpp"

#include <string_view>

namespace feature
{
// These optional, locally bundled maps have detail indexes beginning at z10.
// Keep their overview treatment separate from World and ordinary country maps.
inline bool IsMikshatSupplementaryMap(std::string_view name)
{
  return name == "desert-ksa-north" || name == "desert-ksa-south" || name == "desert-kuwait" || name == "desert-qatar";
}

inline bool IsMikshatOverviewGeometry(FeatureType & feature)
{
  auto const geometry = feature.GetGeomType();
  static ftypes::BaseCheckerEx const protectedAreas(
      {{"boundary", "national_park"}, {"boundary", "protected_area"}, {"leisure", "nature_reserve"}});
  if (geometry == GeomType::Line)
  {
    static ftypes::BaseCheckerEx const lines({{"waterway", "river"}, {"waterway", "stream"}, {"highway", "track"}});
    return lines(feature) || protectedAreas(feature);
  }
  if (geometry == GeomType::Area)
  {
    static ftypes::BaseCheckerEx const vegetation({{"landuse", "meadow"}, {"natural", "grassland"}});
    return vegetation(feature) || ftypes::IsNamedFayda(feature) || protectedAreas(feature);
  }
  return false;
}

// Called by the renderer only after lightweight style rejection. Styling and
// tile zoom stay unchanged; decode the authentic coordinates of these optional
// maps, whose low-detail geometry may be absent at the 20 km ruler and the
// following detail zooms.
inline void PrepareMikshatOverviewGeometry(FeatureType & feature, int drawScale)
{
  auto const & info = feature.GetID().m_mwmId.GetInfo();
  if (drawScale >= 9 && drawScale <= 14 && info && IsMikshatSupplementaryMap(info->GetCountryName()) &&
      IsMikshatOverviewGeometry(feature))
  {
    feature.ResetGeometry();
    feature.GetLimitRect(FeatureType::BEST_GEOMETRY);
  }
}
}  // namespace feature
