#pragma once

#include "indexer/feature.hpp"
#include "indexer/ftypes_matcher.hpp"

#include <cstdint>
#include <string_view>

namespace feature
{
uint8_t constexpr kMikshatProtectedVisibility = 1;
uint8_t constexpr kMikshatOutdoorVisibility = 2;
uint8_t constexpr kMikshatSandyVisibility = 4;
uint8_t constexpr kMikshatAllVisibility = 7;

// The GUI passes the distance represented by its metric ruler, independently
// of the user's unit preference. These are metres, never drawing zoom levels.
inline uint8_t GetMikshatOutdoorVisibility(double rulerMetres)
{
  uint8_t visible = 0;
  if (rulerMetres <= 50000.0)
    visible |= kMikshatProtectedVisibility;
  if (rulerMetres <= 20000.0)
    visible |= kMikshatOutdoorVisibility;
  if (rulerMetres <= 15000.0)
    visible |= kMikshatSandyVisibility;
  return visible;
}

inline bool IsMikshatProtectedType(uint32_t type)
{
  static ftypes::BaseCheckerEx const checker(
      {{"boundary", "national_park"}, {"boundary", "protected_area"}, {"leisure", "nature_reserve"}});
  return checker(type);
}

inline uint8_t GetMikshatOutdoorTypeVisibility(uint32_t type, FeatureType & feature)
{
  if (IsMikshatProtectedType(type))
    return kMikshatProtectedVisibility;
  static ftypes::BaseCheckerEx const sandy({{"natural", "desert"}, {"natural", "beach", "sand"}});
  if (sandy(type))
    return kMikshatSandyVisibility;
  // The audited sand-landmark records use the generic locality category in
  // both official and bundled maps. Faydas keep their separate green policy.
  static ftypes::BaseCheckerEx const locality({{"place", "locality"}});
  if (locality(type) && feature.HasName() && !ftypes::IsNamedFayda(feature))
    return kMikshatSandyVisibility;
  static ftypes::BaseCheckerEx const waterway({{"waterway", "river"}, {"waterway", "stream"}});
  if (waterway(type))
    return kMikshatOutdoorVisibility;
  static ftypes::BaseCheckerEx const roads({{"highway"}});
  if (feature.GetGeomType() == GeomType::Line && roads(type) && ftypes::IsUnpavedRoad(feature::TypesHolder(feature)))
    return kMikshatOutdoorVisibility;
  static ftypes::BaseCheckerEx const fayda(
      {{"place", "locality"}, {"landuse", "meadow"}, {"natural", "grassland"}, {"natural", "wetland"}});
  if (fayda(type) && ftypes::IsNamedFayda(feature))
    return kMikshatOutdoorVisibility;
  return 0;
}

inline uint8_t GetMikshatOutdoorFeatureVisibility(FeatureType & feature)
{
  uint8_t visible = 0;
  for (auto const type : feature::TypesHolder(feature))
    visible |= GetMikshatOutdoorTypeVisibility(type, feature);
  return visible;
}

// These optional, locally bundled maps have detail indexes beginning at z10.
// Keep their overview treatment separate from World and ordinary country maps.
inline bool IsMikshatSupplementaryMap(std::string_view name)
{
  return name == "desert-ksa-north" || name == "desert-ksa-south" || name == "desert-kuwait" || name == "desert-qatar";
}

inline bool IsMikshatOverviewGeometry(FeatureType & feature)
{
  auto const geometry = feature.GetGeomType();
  return (geometry == GeomType::Line || geometry == GeomType::Area) && GetMikshatOutdoorFeatureVisibility(feature) != 0;
}

// Called by the renderer only after lightweight style rejection. Styling and
// tile zoom stay unchanged; decode the authentic coordinates of these optional
// maps, whose low-detail geometry may be absent at the 50 km ruler and the
// following detail zooms.
inline void PrepareMikshatOverviewGeometry(FeatureType & feature, int drawScale)
{
  auto const & info = feature.GetID().m_mwmId.GetInfo();
  if (drawScale >= 6 && drawScale <= 14 && info && info->GetType() == MwmInfo::COUNTRY &&
      IsMikshatOverviewGeometry(feature))
  {
    if (!feature.IsEmptyGeometry(drawScale))
      return;
    feature.ResetGeometry();
    feature.GetLimitRect(FeatureType::BEST_GEOMETRY);
  }
}
}  // namespace feature
