#include "testing/testing.hpp"

#include "map/features_fetcher.hpp"

#include "indexer/classificator.hpp"
#include "indexer/classificator_loader.hpp"
#include "indexer/feature_algo.hpp"
#include "indexer/ftypes_matcher.hpp"
#include "indexer/scales.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

namespace mwm_index_test
{
using namespace std;

namespace
{
class CheckNonEmptyGeometry
{
public:
  vector<FeatureID> m_ids;

  void operator()(FeatureID const & id) { m_ids.push_back(id); }

  void operator()(FeatureType & ft)
  {
    bool res = false;
    ft.ForEachPoint([&res](m2::PointD const &) { res = true; }, m_scale);
    ft.ForEachTriangle([&res](m2::PointD const &, m2::PointD const &, m2::PointD const &) { res = true; }, m_scale);

    TEST(res, (ft.DebugString(), "Scale =", m_scale));
  }

  void SetScale(int scale)
  {
    m_ids.clear();
    m_scale = scale;
  }

private:
  int m_scale;
};

bool RunTest(string const & countryFileName, int lowS, int highS)
{
  FeaturesFetcher src;
  auto p = src.RegisterMap(platform::LocalCountryFile::MakeForTesting(countryFileName));
  if (p.second != MwmSet::RegResult::Success)
    return false;

  MwmSet::MwmId const & id = p.first;
  ASSERT(id.IsAlive(), ());

  version::Format const version = id.GetInfo()->m_version.GetFormat();
  if (version == version::Format::unknownFormat)
    return false;

  CheckNonEmptyGeometry doCheck;
  for (int scale = lowS; scale <= highS; ++scale)
  {
    doCheck.SetScale(scale);
    src.ForEachFeatureID(mercator::Bounds::FullRect(), doCheck, scale);
    src.ReadFeatures(doCheck, doCheck.m_ids);
  }

  return true;
}
}  // namespace

UNIT_TEST(ForEachFeatureID_Test)
{
  classificator::Load();

  TEST(RunTest("World", 0, scales::GetUpperWorldScale()), ());
  TEST(RunTest("WorldCoasts", 0, scales::GetUpperWorldScale()), ());
  // TEST(RunTest("Belarus", scales::GetUpperWorldScale() + 1, scales::GetUpperStyleScale()), ());
  TEST(RunTest("minsk-pass", scales::GetUpperWorldScale() + 1, scales::GetUpperStyleScale()), ());
}

UNIT_TEST(ForEachFeatureID_WorldGeometryScaleContract)
{
  classificator::Load();
  FeaturesFetcher src;
  auto const registered = src.RegisterMap(platform::LocalCountryFile::MakeForTesting("World"));
  TEST_EQUAL(registered.second, MwmSet::RegResult::Success, ("The bundled World fixture must register"));
  FeaturesLoaderGuard loader(src.GetDataSource(), registered.first);
  std::array<uint32_t, 2> constexpr reportedIds = {14409, 14858};
  TEST_GREATER(loader.GetNumFeatures(), reportedIds.back(), ("The World fixture must contain the reported features"));

  size_t totalReturned = 0;
  size_t totalEmpty = 0;
  for (int scale = 0; scale <= scales::GetUpperWorldScale(); ++scale)
  {
    std::vector<FeatureID> ids;
    src.ForEachFeatureID(mercator::Bounds::FullRect(), [&](FeatureID const & id) { ids.push_back(id); }, scale);
    std::sort(ids.begin(), ids.end());
    ids.erase(std::unique(ids.begin(), ids.end()), ids.end());
    size_t emptyAtScale = 0;
    src.GetDataSource().ReadFeatures([&](FeatureType & ft)
    {
      // Validate availability without calling GetLimitRect, whose assertion
      // is precisely what a wrongly inflated query can reach in the renderer.
      if (ft.IsEmptyGeometry(scale))
        ++emptyAtScale;
    }, ids);
    totalReturned += ids.size();
    totalEmpty += emptyAtScale;
    std::cout << "MIKSHAT_WORLD_GEOMETRY {\"event\":\"scale\",\"scale\":" << scale << ",\"returned\":" << ids.size()
              << ",\"emptyGeometry\":" << emptyAtScale << "}\n";

    for (uint32_t const featureIndex : reportedIds)
    {
      // A new FeatureType per zoom avoids retaining another zoom's parsed
      // geometry. Report both query membership and the original data contract.
      auto ft = loader.GetFeatureByIndex(featureIndex);
      TEST(ft, (featureIndex));
      bool const returned = std::binary_search(ids.begin(), ids.end(), FeatureID(registered.first, featureIndex));
      bool const empty = ft->IsEmptyGeometry(scale);
      std::cout << "MIKSHAT_WORLD_GEOMETRY {\"event\":\"reported-feature\",\"scale\":" << scale
                << ",\"id\":" << featureIndex << ",\"returned\":" << (returned ? "true" : "false")
                << ",\"emptyGeometry\":" << (empty ? "true" : "false") << "}\n";
    }
  }
  std::cout << "MIKSHAT_WORLD_GEOMETRY {\"event\":\"summary\",\"scales\":" << scales::GetUpperWorldScale() + 1
            << ",\"returned\":" << totalReturned << ",\"emptyGeometry\":" << totalEmpty << "}" << std::endl;
  TEST_GREATER(totalReturned, 0, ("The World fixture must exercise real indexed features"));
  TEST_EQUAL(totalEmpty, 0, ("Every returned World feature must have geometry at the requested zoom"));
}

namespace
{
std::vector<FeatureID> ReadOverviewIds(FeaturesFetcher const & source, m2::RectD const & rect, int scale,
                                       bool rendering)
{
  std::vector<FeatureID> ids;
  auto const append = [&](FeatureID const & id) { ids.push_back(id); };
  if (rendering)
    source.ForEachFeatureIDForRendering(rect, append, scale);
  else
    source.ForEachFeatureID(rect, append, scale);
  std::sort(ids.begin(), ids.end());
  TEST(std::adjacent_find(ids.begin(), ids.end()) == ids.end(), ("Renderer IDs must remain unique"));
  return ids;
}
}  // namespace

UNIT_TEST(MikshatOverview_PreservesWorldAndCancellation)
{
  classificator::Load();
  FeaturesFetcher source;
  auto const world = source.RegisterMap(platform::LocalCountryFile::MakeForTesting("World"));
  TEST_EQUAL(world.second, MwmSet::RegResult::Success, ());
  for (int const scale : {0, 8, 9, 10, 11, 17})
  {
    // Whole-world and unsupported-zoom calls must not turn into country scans.
    auto const normal = ReadOverviewIds(source, mercator::Bounds::FullRect(), scale, false);
    auto const rendered = ReadOverviewIds(source, mercator::Bounds::FullRect(), scale, true);
    TEST_EQUAL(rendered, normal, (scale));
  }
  auto const rect = mercator::RectByCenterXYAndSizeInMeters(mercator::FromLatLon(25.4031, 47.2858166667), 60000.0);
  for (int const scale : {9, 10})
  {
    auto const normal = ReadOverviewIds(source, rect, scale, false);
    auto const rendered = ReadOverviewIds(source, rect, scale, true);
    TEST_EQUAL(rendered, normal, ("World must keep its native geometry/index zoom", scale));
    source.GetDataSource().ReadFeatures(
        [&](FeatureType & feature) { TEST(!feature.IsEmptyGeometry(scale), (feature.GetID(), scale)); }, rendered);
  }

  size_t callbacks = 0;
  source.ForEachFeatureIDForRendering(mercator::Bounds::FullRect(), [&](FeatureID const &) { ++callbacks; }, 9,
                                      [] { return true; });
  TEST_EQUAL(callbacks, 0, ("Already-cancelled tile must not expose features"));
  source.ForEachFeatureIDForRendering(mercator::Bounds::FullRect(), [&](FeatureID const &) { ++callbacks; }, 9,
                                      [&] { return callbacks >= 5; });
  TEST_EQUAL(callbacks, 5, ("Tile cancellation must reach the renderer ID provider"));
}

#ifdef MIKSHAT_SAUDI_OVERVIEW_TESTS
UNIT_TEST(MikshatOverview_SaudiIndexedPoints)
{
  classificator::Load();
  char const * northPath = std::getenv("MIKSHAT_SAUDI_NORTH_MWM_PATH");
  char const * southPath = std::getenv("MIKSHAT_SAUDI_SOUTH_MWM_PATH");
  TEST(northPath && *northPath && southPath && *southPath,
       ("Supply both verified official Saudi fixtures; missing data is not a passing test"));
  FeaturesFetcher source;
  auto northFile = platform::LocalCountryFile::MakeTemporary(northPath);
  northFile.SyncWithDisk();
  auto const north = source.RegisterMap(northFile);
  TEST_EQUAL(north.second, MwmSet::RegResult::Success, (northPath));
  auto southFile = platform::LocalCountryFile::MakeTemporary(southPath);
  southFile.SyncWithDisk();
  auto const south = source.RegisterMap(southFile);
  TEST_EQUAL(south.second, MwmSet::RegResult::Success, (southPath));
  auto const world = source.RegisterMap(platform::LocalCountryFile::MakeForTesting("World"));
  TEST_EQUAL(world.second, MwmSet::RegResult::Success, ());

  std::array<ms::LatLon, 3> const locations = {{{26.2317333333, 44.9453}, {25.4031, 47.2858166667}, {24.65, 46.71}}};
  size_t totalPromoted = 0;
  for (size_t location = 0; location < locations.size(); ++location)
  {
    auto const center = mercator::FromLatLon(locations[location]);
    // The helper takes half-extents: this is a 40 km viewport, within a
    // draw-zoom 10 tile's allowed projected extent at Saudi latitudes.
    auto const rect = mercator::RectByCenterXYAndSizeInMeters(center, 20000.0);
    for (int const scale : {9, 10})
    {
      auto const start = std::chrono::steady_clock::now();
      auto const normal = ReadOverviewIds(source, rect, scale, false);
      auto const rendered = ReadOverviewIds(source, rect, scale, true);
      TEST(std::includes(rendered.begin(), rendered.end(), normal.begin(), normal.end()), (location, scale));
      std::vector<FeatureID> promoted;
      std::set_difference(rendered.begin(), rendered.end(), normal.begin(), normal.end(), std::back_inserter(promoted));
      TEST_LESS_OR_EQUAL(promoted.size(), 512, ("Overview additions have a hard memory/count budget"));
      source.GetDataSource().ReadFeatures([&](FeatureType & feature)
      {
        TEST(feature.GetID().m_mwmId == north.first || feature.GetID().m_mwmId == south.first,
             ("Only downloaded country points are promoted"));
        TEST_EQUAL(feature.GetGeomType(), feature::GeomType::Point, (feature.GetID()));
        TEST(rect.IsPointInside(feature.GetCenter()), ("Spatial index covering must not leak off-tile points"));
        TEST(!feature.IsEmptyGeometry(scale), ("Point geometry remains valid at the actual draw zoom"));
      }, promoted);
      totalPromoted += promoted.size();
      auto const elapsed =
          std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
      std::cout << "MIKSHAT_OVERVIEW {\"location\":" << location << ",\"drawZoom\":" << scale
                << ",\"nativeIds\":" << normal.size() << ",\"promotedPoints\":" << promoted.size()
                << ",\"milliseconds\":" << elapsed << "}\n";
    }
  }
  TEST_GREATER(totalPromoted, 0, ("The real official map must prove that previously indexed-out points are added"));

  // The supplied reference pin is approximately 6.1 km north of this
  // authentic South-map locality. Preserve its stored OSM position.
  FeaturesLoaderGuard loader(source.GetDataSource(), south.first);
  uint32_t constexpr faydaIndex = 609861;
  TEST_GREATER(loader.GetNumFeatures(), faydaIndex, ());
  auto fayda = loader.GetFeatureByIndex(faydaIndex);
  TEST(fayda, ());
  TEST_EQUAL(fayda->GetGeomType(), feature::GeomType::Point, ());
  TEST(feature::TypesHolder(*fayda).Has(classif().GetTypeByPath({"place", "locality"})), ());
  bool hasExpectedName = false;
  fayda->ForEachName([&](int8_t, std::string_view name)
  {
    hasExpectedName = hasExpectedName || name == "فيضة الخويش";
    return true;
  });
  TEST(hasExpectedName, ("The actual feature, not a synthetic name, must be inspected"));
  TEST(ftypes::IsNamedFayda(*fayda), ());
  auto const stored = mercator::ToLatLon(fayda->GetCenter());
  TEST_ALMOST_EQUAL_ABS(stored.m_lat, 25.3479422061, 1e-6, ());
  TEST_ALMOST_EQUAL_ABS(stored.m_lon, 47.2901334412, 1e-6, ());
  auto const referenceViewport = mercator::RectByCenterXYAndSizeInMeters(mercator::FromLatLon(locations[1]), 20000.0);
  TEST(referenceViewport.IsPointInside(fayda->GetCenter()), ());
  for (int const scale : {9, 10})
  {
    auto const native = ReadOverviewIds(source, referenceViewport, scale, false);
    auto const rendered = ReadOverviewIds(source, referenceViewport, scale, true);
    bool const wasVisible = std::binary_search(native.begin(), native.end(), fayda->GetID());
    bool const isVisible = std::binary_search(rendered.begin(), rendered.end(), fayda->GetID());
    TEST(isVisible, ("The authentic named fayda must be returned in the user's overview viewport", scale));
    TEST(!fayda->IsEmptyGeometry(scale), ());
    std::cout << "MIKSHAT_FAYDA {\"feature\":" << faydaIndex << ",\"drawZoom\":" << scale
              << ",\"nativeVisible\":" << (wasVisible ? "true" : "false")
              << ",\"overviewVisible\":" << (isVisible ? "true" : "false") << ",\"latitude\":" << std::setprecision(12)
              << stored.m_lat << ",\"longitude\":" << stored.m_lon << "}\n";
  }
}
#endif  // MIKSHAT_SAUDI_OVERVIEW_TESTS
}  // namespace mwm_index_test
