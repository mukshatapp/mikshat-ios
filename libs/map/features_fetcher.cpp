#include "map/features_fetcher.hpp"

#include "platform/platform.hpp"

#include "indexer/classificator_loader.hpp"
#include "indexer/ftypes_matcher.hpp"
#include "indexer/mikshat_map_visibility.hpp"

#include "base/assert.hpp"
#include "base/logging.hpp"

#include <algorithm>
#include <set>

using platform::CountryFile;
using platform::LocalCountryFile;

namespace
{
bool IsOverviewPoint(FeatureType & feature)
{
  if (feature.GetGeomType() != feature::GeomType::Point)
    return false;
  static ftypes::BaseCheckerEx const resources({{"amenity", "fuel"},
                                                {"amenity", "drinking_water"},
                                                {"amenity", "water_point"},
                                                {"man_made", "water_tap"},
                                                {"man_made", "water_well"},
                                                {"natural", "spring"},
                                                {"natural", "hot_spring"},
                                                {"place", "village"},
                                                {"place", "hamlet"}});
  return resources(feature) || ftypes::IsNamedFayda(feature);
}
}  // namespace

void FeaturesFetcher::ForEachFeatureIDForRendering(m2::RectD const & rect,
                                                   std::function<void(FeatureID const &)> const & fn, int scale,
                                                   DataSource::StopSearchCallback const & stop) const
{
  auto const cancelled = [&] { return stop && stop(); };
  if (cancelled())
    return;
  // Keep ordinary queries streaming, including detail zooms when no optional
  // map intersects the tile and non-tile-sized diagnostics/search requests.
  bool const pointOverview = scale == 9 || scale == 10;
  bool const overview = scale >= 9 && scale <= 14;
  double const maxSpan = overview ? mercator::Bounds::kRangeX / (1u << (scale - 1)) : 0.0;
  bool const tileOverview = overview && rect.IsValid() && rect.SizeX() <= maxSpan && rect.SizeY() <= maxSpan;
  std::vector<std::shared_ptr<MwmInfo>> maps;
  if (tileOverview)
    m_dataSource.GetMwmsInfo(maps);
  bool const hasSupplementary = std::any_of(maps.begin(), maps.end(), [&](auto const & info)
  {
    return info->IsRegistered() && feature::IsMikshatSupplementaryMap(info->GetCountryName()) &&
           rect.IsIntersect(info->m_bordersRect);
  });
  if (!tileOverview || (!pointOverview && !hasSupplementary))
  {
    ForEachFeatureID(rect, [&](FeatureID const & id)
    {
      if (!cancelled())
        fn(id);
    }, scale);
    return;
  }
  std::vector<FeatureID> ids;
  ForEachFeatureID(rect, [&](FeatureID const & id) { ids.push_back(id); }, scale);
  if (cancelled())
    return;
  std::sort(ids.begin(), ids.end());
  ids.erase(std::unique(ids.begin(), ids.end()), ids.end());

  // Tile-sized queries from the 20 km ruler through detail zooms. Do not
  // turn a whole-world, navigation, or search request into a high-detail scan.
  {
    size_t constexpr maxCountries = 8;
    size_t constexpr maxInspected = 32768;
    size_t constexpr maxInspectedPerCountry = maxInspected / maxCountries;
    size_t constexpr maxAdded = 512;
    size_t inspected = 0;
    size_t countries = 0;
    size_t const pointLimit = hasSupplementary ? maxAdded / 2 : maxAdded;
    size_t const geometryLimit = maxAdded - pointLimit;
    std::set<FeatureID> extraPoints;
    std::set<FeatureID> extraGeometry;
    auto const finished = [&]
    {
      return cancelled() || inspected >= maxInspected ||
             (extraPoints.size() >= pointLimit && extraGeometry.size() >= geometryLimit);
    };
    // A user-selected supplementary map gets its own turn before the ordinary
    // country landmark pass, so dense official POIs cannot exhaust its budget.
    std::stable_sort(maps.begin(), maps.end(), [](auto const & lhs, auto const & rhs)
    {
      return feature::IsMikshatSupplementaryMap(lhs->GetCountryName()) >
             feature::IsMikshatSupplementaryMap(rhs->GetCountryName());
    });
    for (auto const & info : maps)
    {
      if (finished() || countries >= maxCountries)
        break;
      bool const supplementary = feature::IsMikshatSupplementaryMap(info->GetCountryName());
      if (!info->IsRegistered() || info->GetType() != MwmInfo::COUNTRY || !rect.IsIntersect(info->m_bordersRect) ||
          (!pointOverview && !supplementary))
        continue;
      ++countries;
      size_t countryInspected = 0;
      auto const countryFinished = [&] { return finished() || countryInspected >= maxInspectedPerCountry; };
      m_dataSource.ForEachInRectForMWM([&](FeatureType & feature)
      {
        ++inspected;
        ++countryInspected;
        auto const & id = feature.GetID();
        if (std::binary_search(ids.begin(), ids.end(), id))
          return;
        if (extraPoints.size() < pointLimit && IsOverviewPoint(feature) && rect.IsPointInside(feature.GetCenter()))
          extraPoints.insert(id);
        else if (supplementary && extraGeometry.size() < geometryLimit && feature::IsMikshatOverviewGeometry(feature))
        {
          feature.ResetGeometry();
          if (rect.IsIntersect(feature.GetLimitRect(FeatureType::BEST_GEOMETRY)))
            extraGeometry.insert(id);
        }
      }, rect, info->m_maxScale, MwmSet::MwmId(info), countryFinished, covering::Spiral);
    }
    ids.insert(ids.end(), extraPoints.begin(), extraPoints.end());
    ids.insert(ids.end(), extraGeometry.begin(), extraGeometry.end());
    // TileInfo requires each MWM's IDs to be contiguous even before its own
    // sorting pass; supplements cannot revisit an earlier country group.
    std::sort(ids.begin(), ids.end());
  }
  for (auto const & id : ids)
  {
    if (cancelled())
      return;
    fn(id);
  }
}

FeaturesFetcher::FeaturesFetcher()
{
  m_dataSource.AddObserver(*this);
}

FeaturesFetcher::~FeaturesFetcher()
{
  m_dataSource.RemoveObserver(*this);
}

// While reading any files (classificator or mwm), there are 2 types of possible exceptions:
// Reader::Exception, FileAbsentException.
// Let's process RootException everywhere, to supress such errors.

void FeaturesFetcher::InitClassificator()
{
  try
  {
    classificator::Load();
  }
  catch (RootException const & e)
  {
    LOG(LERROR, ("Classificator read error: ", e.what()));
  }
}

std::pair<MwmSet::MwmId, MwmSet::RegResult> FeaturesFetcher::RegisterMap(LocalCountryFile const & localFile)
{
  try
  {
    auto result = m_dataSource.RegisterMap(localFile);
    if (result.second != MwmSet::RegResult::Success)
    {
      LOG(LWARNING, ("Can't add map", localFile.GetCountryName(), "(", result.second, ").",
                     "Probably it's already added or has newer data version."));
    }
    else
    {
      MwmSet::MwmId const & id = result.first;
      ASSERT(id.IsAlive(), ());
      m_rect.Add(id.GetInfo()->m_bordersRect);
    }

    return result;
  }
  catch (RootException const & ex)
  {
    LOG(LERROR, ("IO error while adding", localFile.GetCountryName(), "map.", ex.Msg()));
    return std::make_pair(MwmSet::MwmId(), MwmSet::RegResult::BadFile);
  }
}

bool FeaturesFetcher::DeregisterMap(CountryFile const & countryFile)
{
  return m_dataSource.Deregister(countryFile);
}

void FeaturesFetcher::Clear()
{
  m_dataSource.Clear();
}

void FeaturesFetcher::ClearCaches()
{
  m_dataSource.ClearCache();
}

m2::RectD FeaturesFetcher::GetWorldRect() const
{
  if (m_rect == m2::RectD())
  {
    // Rect is empty when no countries are loaded, return max global rect.
    return mercator::Bounds::FullRect();
  }
  return m_rect;
}

void FeaturesFetcher::OnMapDeregistered(platform::LocalCountryFile const & localFile)
{
  if (m_onMapDeregistered)
    m_onMapDeregistered(localFile);
}
