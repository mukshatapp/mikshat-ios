#include "map/features_fetcher.hpp"

#include "platform/platform.hpp"

#include "search/cancel_exception.hpp"
#include "search/categories_cache.hpp"
#include "search/mwm_context.hpp"

#include "indexer/classificator.hpp"
#include "indexer/classificator_loader.hpp"
#include "indexer/ftypes_matcher.hpp"
#include "indexer/mikshat_map_visibility.hpp"

#include "base/assert.hpp"
#include "base/checked_cast.hpp"
#include "base/logging.hpp"

#include <algorithm>
#include <set>

using platform::CountryFile;
using platform::LocalCountryFile;

namespace
{
class RenderingSearchCancellation final : public base::Cancellable
{
public:
  explicit RenderingSearchCancellation(DataSource::StopSearchCallback const & stop) : m_stop(stop) {}

  bool IsCancelled() const override { return (m_stop && m_stop()) || base::Cancellable::IsCancelled(); }

private:
  DataSource::StopSearchCallback const & m_stop;
};

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
                                                   DataSource::StopSearchCallback const & stop,
                                                   uint8_t outdoorVisibility) const
{
  auto const cancelled = [&] { return stop && stop(); };
  if (cancelled())
    return;
  // A category's actual-ruler tier comes from the requesting screen. Whole-map
  // diagnostics and World keep their native index/geometry contracts.
  bool const pointOverview = scale == 9 || scale == 10;
  bool const overview = scale >= 6 && scale <= 14;
  double const maxSpan = overview ? mercator::Bounds::kRangeX / (1u << (scale - 1)) : 0.0;
  bool const tileOverview = overview && rect.IsValid() && rect.SizeX() <= maxSpan && rect.SizeY() <= maxSpan;
  bool const outdoorOverview = (outdoorVisibility & feature::kMikshatAllVisibility) != 0;
  if (!tileOverview || (!pointOverview && !outdoorOverview))
  {
    ForEachFeatureID(rect, [&](FeatureID const & id)
    {
      if (!cancelled())
        fn(id);
    }, scale);
    return;
  }

  std::vector<std::shared_ptr<MwmInfo>> maps;
  m_dataSource.GetMwmsInfo(maps);
  bool const hasCountry = std::any_of(maps.begin(), maps.end(), [&](auto const & info)
  { return info->IsRegistered() && info->GetType() == MwmInfo::COUNTRY && rect.IsIntersect(info->m_bordersRect); });
  if (!hasCountry)
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

  size_t constexpr maxCountries = 8;
  size_t constexpr maxInspected = 32768;
  size_t constexpr maxInspectedPerCountry = maxInspected / maxCountries;
  size_t constexpr maxProtected = 128;
  size_t constexpr maxPoints = 256;
  size_t constexpr maxGeometry = 256;
  std::set<FeatureID> protectedFeatures;
  std::set<FeatureID> extraPoints;
  std::set<FeatureID> extraGeometry;

  // The bundled supplementary maps get their own turn before dense official
  // map data. Every Country source otherwise follows the same category policy.
  std::stable_sort(maps.begin(), maps.end(), [](auto const & lhs, auto const & rhs)
  {
    return feature::IsMikshatSupplementaryMap(lhs->GetCountryName()) >
           feature::IsMikshatSupplementaryMap(rhs->GetCountryName());
  });

  // Query rare protected classes first, without materializing a full-detail
  // spatial index. Select Country maps before category retrieval: World never
  // enters this query, and only a bounded number of authentic features decode.
  // Search-index retrieval itself also polls the requesting tile's cancellation.
  // Old indexes without category records retain the bounded spatial fallback.
  if ((outdoorVisibility & feature::kMikshatProtectedVisibility) != 0)
  {
    RenderingSearchCancellation const cancellable(stop);
    auto const & c = classif();
    search::CategoriesCache cache(std::vector<uint32_t>{c.GetTypeByPath({"boundary", "national_park"}),
                                                        c.GetTypeByPath({"boundary", "protected_area"}),
                                                        c.GetTypeByPath({"leisure", "nature_reserve"})},
                                  cancellable);
    size_t countries = 0;
    try
    {
      for (auto const & info : maps)
      {
        if (cancelled())
          return;
        if (countries >= maxCountries || protectedFeatures.size() >= maxProtected)
          break;
        if (!info->IsRegistered() || info->GetType() != MwmInfo::COUNTRY || !rect.IsIntersect(info->m_bordersRect))
          continue;
        ++countries;
        auto handle = m_dataSource.GetMwmHandleById(MwmSet::MwmId(info));
        if (!handle.IsAlive() || !handle.GetValue()->HasSearchIndex())
          continue;
        if (cancelled())
          return;
        search::MwmContext const context(std::move(handle));
        auto const candidates = cache.Get(context);
        if (cancelled())
          return;
        if (candidates.IsEmpty())
          continue;
        // Category retrieval can cover a whole Country. Bound feature decoding
        // before testing authentic geometry against this tile's rectangle.
        candidates.Take(maxProtected * 2)
            .ForEach([&](uint64_t index)
        {
          if (cancelled() || protectedFeatures.size() >= maxProtected)
            return;
          FeatureID const id(context.GetId(), base::asserted_cast<uint32_t>(index));
          if (std::binary_search(ids.begin(), ids.end(), id))
            return;
          auto feature = context.GetFeature(id.m_index);
          if (!feature || cancelled() ||
              (feature::GetMikshatOutdoorFeatureVisibility(*feature) & feature::kMikshatProtectedVisibility) == 0)
            return;
          feature::PrepareMikshatOverviewGeometry(*feature, scale);
          if (!feature->IsEmptyGeometry(scale) && rect.IsIntersect(feature->GetLimitRect(scale)))
            protectedFeatures.insert(id);
        });
      }
    }
    catch (search::CancelException const &)
    {
      return;
    }
  }

  size_t inspected = 0;
  size_t countries = 0;
  auto const finished = [&]
  {
    return cancelled() || inspected >= maxInspected ||
           (extraPoints.size() >= maxPoints && extraGeometry.size() >= maxGeometry &&
            protectedFeatures.size() >= maxProtected);
  };
  for (auto const & info : maps)
  {
    if (finished() || countries >= maxCountries)
      break;
    if (!info->IsRegistered() || info->GetType() != MwmInfo::COUNTRY || !rect.IsIntersect(info->m_bordersRect))
      continue;
    ++countries;
    size_t countryInspected = 0;
    auto const countryFinished = [&] { return finished() || countryInspected >= maxInspectedPerCountry; };
    m_dataSource.ForEachInRectForMWM([&](FeatureType & feature)
    {
      ++inspected;
      ++countryInspected;
      auto const & id = feature.GetID();
      if (std::binary_search(ids.begin(), ids.end(), id) || protectedFeatures.contains(id))
        return;
      auto const category = feature::GetMikshatOutdoorFeatureVisibility(feature) & outdoorVisibility;
      bool const point = feature.GetGeomType() == feature::GeomType::Point;
      if (point && extraPoints.size() < maxPoints && ((category != 0) || (pointOverview && IsOverviewPoint(feature))) &&
          rect.IsPointInside(feature.GetCenter()))
      {
        extraPoints.insert(id);
      }
      else if (!point && category != 0 && feature::IsMikshatOverviewGeometry(feature))
      {
        bool const protectedArea = (category & feature::kMikshatProtectedVisibility) != 0;
        if (protectedArea ? protectedFeatures.size() >= maxProtected : extraGeometry.size() >= maxGeometry)
          return;
        feature::PrepareMikshatOverviewGeometry(feature, scale);
        if (!feature.IsEmptyGeometry(scale) && rect.IsIntersect(feature.GetLimitRect(scale)))
          (protectedArea ? protectedFeatures : extraGeometry).insert(id);
      }
    }, rect, info->m_maxScale, MwmSet::MwmId(info), countryFinished, covering::Spiral);
  }
  ids.insert(ids.end(), protectedFeatures.begin(), protectedFeatures.end());
  ids.insert(ids.end(), extraPoints.begin(), extraPoints.end());
  ids.insert(ids.end(), extraGeometry.begin(), extraGeometry.end());
  // TileInfo requires each MWM's IDs to be contiguous before its own sorting.
  std::sort(ids.begin(), ids.end());
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
