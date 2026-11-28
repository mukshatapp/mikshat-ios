#pragma once

#include <cstdint>

namespace df::mukshat
{
enum class MapDetailKind
{
  Other,
  IntermittentStream,
  DirtRoad,
  Scrub,
  PowerLine
};

using DetailVisibilityMask = uint8_t;
inline constexpr DetailVisibilityMask kShowDirtRoads = 1;
inline constexpr DetailVisibilityMask kShowTwoKilometreDetails = 2;
inline constexpr DetailVisibilityMask kAllDetailVisibility = kShowDirtRoads | kShowTwoKilometreDetails;
// Matches gui::RulerHelper's ground-distance probe; independent of the displayed units.
inline constexpr double kMinimumRulerPixelWidth = 60.0;

// The ruler rounds strictly upward through 1/2/5 units: exactly 2000 m displays 5 km.
inline constexpr DetailVisibilityMask GetDetailVisibilityMask(double minimumRulerDistanceMeters)
{
  DetailVisibilityMask mask = 0;
  if (minimumRulerDistanceMeters < 5000.0)
    mask |= kShowDirtRoads;
  if (minimumRulerDistanceMeters < 2000.0)
    mask |= kShowTwoKilometreDetails;
  return mask;
}

inline constexpr bool CanShow(MapDetailKind kind, DetailVisibilityMask mask)
{
  switch (kind)
  {
  case MapDetailKind::DirtRoad: return (mask & kShowDirtRoads) != 0;
  case MapDetailKind::IntermittentStream:
  case MapDetailKind::PowerLine: return (mask & kShowTwoKilometreDetails) != 0;
  case MapDetailKind::Other:
  case MapDetailKind::Scrub: return true;
  }
  return true;
}
}  // namespace df::mukshat
