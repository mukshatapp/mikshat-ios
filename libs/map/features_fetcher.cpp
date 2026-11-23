#include "map/features_fetcher.hpp"

#include "platform/platform.hpp"

#include "indexer/classificator_loader.hpp"
#include "indexer/ftypes_matcher.hpp"

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
  // Keep the ordinary stream path allocation-free at every other zoom and
  // for non-tile-sized requests such as whole-world/search diagnostics.
  bool const overview = scale == 9 || scale == 10;
  double const maxSpan = overview ? mercator::Bounds::kRangeX / (1u << (scale - 1)) : 0.0;
  if (!overview || !rect.IsValid() || rect.SizeX() > maxSpan || rect.SizeY() > maxSpan)
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

  // A tile-sized query at the 20 km ruler's native draw zooms only. Do not
  // turn a whole-world, navigation, or search request into a high-detail scan.
  {
    size_t constexpr maxCountries = 4;
    size_t constexpr maxInspected = 16384;
    size_t constexpr maxInspectedPerCountry = maxInspected / maxCountries;
    size_t constexpr maxAdded = 512;
    size_t inspected = 0;
    size_t countries = 0;
    std::set<FeatureID> extra;
    auto const finished = [&] { return cancelled() || inspected >= maxInspected || extra.size() >= maxAdded; };
    std::vector<std::shared_ptr<MwmInfo>> maps;
    m_dataSource.GetMwmsInfo(maps);
    for (auto const & info : maps)
    {
      if (finished() || countries >= maxCountries)
        break;
      if (info->GetType() != MwmInfo::COUNTRY || !rect.IsIntersect(info->m_bordersRect))
        continue;
      ++countries;
      size_t countryInspected = 0;
      auto const countryFinished = [&] { return finished() || countryInspected >= maxInspectedPerCountry; };
      m_dataSource.ForEachInRectForMWM([&](FeatureType & feature)
      {
        ++inspected;
        ++countryInspected;
        if (!IsOverviewPoint(feature) || !rect.IsPointInside(feature.GetCenter()))
          return;
        auto const & id = feature.GetID();
        if (!std::binary_search(ids.begin(), ids.end(), id))
          extra.insert(id);
      }, rect, info->m_maxScale, MwmSet::MwmId(info), countryFinished, covering::Spiral);
    }
    ids.insert(ids.end(), extra.begin(), extra.end());
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
