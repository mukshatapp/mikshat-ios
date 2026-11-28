#pragma once

#include "drape_frontend/mukshat_detail_visibility.hpp"

#include "indexer/classificator.hpp"
#include "indexer/feature.hpp"
#include "indexer/ftypes_matcher.hpp"

namespace df::mukshat
{
inline MapDetailKind ClassifyMapDetail(FeatureType & f)
{
  feature::TypesHolder const types(f);
  if (f.GetGeomType() == feature::GeomType::Line)
  {
    static ftypes::BaseCheckerEx const streamTunnel({{"waterway", "stream", "tunnel"}});
    static ftypes::BaseCheckerEx const intermittentStream({{"waterway", "stream", "intermittent"}});
    if (!streamTunnel(types) && intermittentStream(types))
      return MapDetailKind::IntermittentStream;

    // Only these above-ground classifier leaves are styled. Location/underground
    // power features are excluded by the generator; never match future descendants.
    static auto const powerLine = classif().GetTypeByPath({"power", "line"});
    static auto const minorPowerLine = classif().GetTypeByPath({"power", "minor_line"});
    for (auto const type : types)
      if (type == powerLine || type == minorPowerLine)
        return MapDetailKind::PowerLine;

    // Match the existing brown presentation, including legacy track subtypes.
    static ftypes::BaseCheckerEx const dirtRoad(
        {{"highway", "track"}, {"psurface", "unpaved_good"}, {"psurface", "unpaved_bad"}});
    if (dirtRoad(types))
      return MapDetailKind::DirtRoad;
  }

  if (f.GetGeomType() != feature::GeomType::Line)
  {
    static ftypes::BaseCheckerEx const scrub({{"natural", "scrub"}});
    if (scrub(types))
      return MapDetailKind::Scrub;
  }
  return MapDetailKind::Other;
}
}  // namespace df::mukshat
