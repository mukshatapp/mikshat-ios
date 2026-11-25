#include "testing/testing.hpp"

#include "map/features_fetcher.hpp"

#include "drape_frontend/stylist.hpp"

#include "indexer/classificator.hpp"
#include "indexer/classificator_loader.hpp"
#include "indexer/feature_algo.hpp"
#include "indexer/ftypes_matcher.hpp"
#include "indexer/mikshat_map_visibility.hpp"
#include "indexer/scales.hpp"
#include "indexer/search_string_utils.hpp"
#include "indexer/transliteration_loader.hpp"

#include "platform/map_compatibility.hpp"

#include <glaze/json.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
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

std::string NormalizeOutdoorName(std::string_view name)
{
  auto value = strings::ToUtf8(search::NormalizeAndSimplifyString(name));
  std::erase(value, ' ');
  return value;
}

// Country releases renumber features. Identify real fixtures by their stored
// location, category and name instead of reusing a previous release's index.
uint32_t FindNamedFeature(FeaturesFetcher const & source, MwmSet::MwmId const & map, std::string_view name,
                          ms::LatLon const & location, uint32_t type, feature::GeomType geometry,
                          double radiusMeters = 1000.0)
{
  auto const center = mercator::FromLatLon(location);
  auto const rect = mercator::RectByCenterXYAndSizeInMeters(center, radiusMeters);
  auto const expectedName = NormalizeOutdoorName(name);
  std::vector<uint32_t> matches;
  source.GetDataSource().ForEachInRectForMWM([&](FeatureType & candidate)
  {
    if (candidate.GetGeomType() != geometry || !feature::TypesHolder(candidate).Has(type) ||
        mercator::DistanceOnEarth(feature::GetCenter(candidate), center) > radiusMeters)
      return;
    bool named = false;
    candidate.ForEachName([&](int8_t, std::string_view value)
    { named = named || NormalizeOutdoorName(value) == expectedName; });
    if (named)
      matches.push_back(candidate.GetID().m_index);
  }, rect, scales::GetUpperScale(), map);
  std::sort(matches.begin(), matches.end());
  matches.erase(std::unique(matches.begin(), matches.end()), matches.end());
  TEST_EQUAL(matches.size(), 1, ("Require one actual named fixture in its recorded region", name, location));
  return matches.front();
}

uint32_t FindReportedTrack(FeaturesFetcher const & source, MwmSet::MwmId const & map)
{
  auto const center = mercator::FromLatLon(28.0 + 0.628 / 60.0, 42.0 + 0.426 / 60.0);
  auto const rect = mercator::RectByCenterXYAndSizeInMeters(center, 100.0);
  auto const trackType = classif().GetTypeByPath({"highway", "track"});
  uint32_t index = std::numeric_limits<uint32_t>::max();
  double nearest = 50.0;
  source.GetDataSource().ForEachInRectForMWM([&](FeatureType & candidate)
  {
    if (candidate.GetGeomType() != feature::GeomType::Line || !feature::TypesHolder(candidate).Has(trackType))
      return;
    double const distance = feature::GetMinDistanceMeters(candidate, center, FeatureType::BEST_GEOMETRY);
    if (distance < nearest)
    {
      nearest = distance;
      index = candidate.GetID().m_index;
    }
  }, rect, scales::GetUpperScale(), map);
  TEST_NOT_EQUAL(index, std::numeric_limits<uint32_t>::max(), ("The user's actual track must remain within 50 m"));
  return index;
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
UNIT_TEST(MikshatOfficialMaps_CurrentReleaseCountriesAndWorld)
{
  classificator::Load();
  std::array<char const *, 3> const keys = {"MIKSHAT_SAUDI_NORTH_MWM_PATH", "MIKSHAT_SAUDI_SOUTH_MWM_PATH",
                                            "MIKSHAT_QATAR_MWM_PATH"};
  std::array<std::string, 3> const countries = {"Saudi Arabia_North", "Saudi Arabia_South", "Qatar"};
  std::array<std::string, 5> paths;
  for (size_t i = 0; i < keys.size(); ++i)
  {
    char const * path = std::getenv(keys[i]);
    TEST(path && *path, ("All three independently verified current official country fixtures are required", keys[i]));
    paths[i] = path;
  }
  paths[3] = "World";
  paths[4] = "WorldCoasts";

  for (size_t i = 0; i < paths.size(); ++i)
  {
    FeaturesFetcher source;
    auto file = i < countries.size() ? platform::LocalCountryFile::MakeTemporary(paths[i])
                                     : platform::LocalCountryFile::MakeForTesting(paths[i]);
    file.SyncWithDisk();
    auto const registered = source.RegisterMap(file);
    TEST_EQUAL(registered.second, MwmSet::RegResult::Success, (paths[i]));
    auto const info = registered.first.GetInfo();
    TEST_EQUAL(info->m_version.GetFormat(), version::Format::lastFormat, (paths[i]));
    TEST_EQUAL(info->m_version.GetVersion(), platform::map_compatibility::kDataVersion, (paths[i]));
    if (i < countries.size())
    {
      TEST_EQUAL(info->GetCountryName(), countries[i], ("Saudi Arabia uses the official named country maps"));
      TEST_EQUAL(info->GetType(), MwmInfo::COUNTRY, ());
      FeaturesLoaderGuard loader(source.GetDataSource(), registered.first);
      TEST(loader.GetContainer().IsExist(SEARCH_INDEX_FILE_TAG), (countries[i]));
      TEST(loader.GetContainer().IsExist(ROUTING_FILE_TAG), (countries[i]));
    }
    else
      TEST_EQUAL(info->GetType(), i == 3 ? MwmInfo::WORLD : MwmInfo::COASTS, (paths[i]));

    size_t inspected = 0;
    int const scale = i < countries.size() ? scales::GetUpperScale() : scales::GetUpperWorldScale();
    source.GetDataSource().ForEachInRectForMWM([&](FeatureType & candidate)
    {
      TEST(!candidate.IsEmptyGeometry(scale), (paths[i], candidate.GetID()));
      size_t types = 0;
      candidate.ForEachType([&](uint32_t type)
      {
        TEST(!classif().GetReadableObjectName(type).empty(), (paths[i], candidate.GetID()));
        ++types;
      });
      TEST_GREATER(types, 0, (paths[i], candidate.GetID()));
      ++inspected;
    }, mercator::Bounds::FullRect(), scale, registered.first, [&] { return inspected >= 200; });
    TEST_EQUAL(inspected, 200,
               ("Each real map must exercise native spatial decoding with the current classifier", paths[i]));
    std::cout << "MIKSHAT_OFFICIAL_RELEASE {\"country\":\"" << info->GetCountryName()
              << "\",\"dataVersion\":" << info->m_version.GetVersion() << ",\"decodedFeatures\":" << inspected << "}\n";
  }
}

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
  uint32_t const faydaIndex =
      FindNamedFeature(source, south.first, "فيضة الخويش", {25.3479422061, 47.2901334412},
                       classif().GetTypeByPath({"place", "locality"}), feature::GeomType::Point);
  TEST_GREATER(loader.GetNumFeatures(), faydaIndex, ());
  auto fayda = loader.GetFeatureByIndex(faydaIndex);
  TEST(fayda, ());
  TEST_EQUAL(fayda->GetGeomType(), feature::GeomType::Point, ());
  TEST(feature::TypesHolder(*fayda).Has(classif().GetTypeByPath({"place", "locality"})), ());
  bool hasExpectedName = false;
  fayda->ForEachName([&](int8_t, std::string_view name)
  { hasExpectedName = hasExpectedName || name == "فيضة الخويش"; });
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

#ifdef MIKSHAT_SUPPLEMENTARY_OVERVIEW_TESTS
namespace
{
struct OutdoorFeatureAuditRecord
{
  std::string m_event;
  std::string m_source;
  uint32_t m_feature = 0;
  std::string m_geometry;
  std::vector<std::string> m_names;
  std::vector<std::string> m_types;
  double m_latitude = 0.0;
  double m_longitude = 0.0;
  double m_distanceMeters = -1.0;
};

std::string NormalizeOutdoorAuditName(std::string_view name)
{
  return NormalizeOutdoorName(name);
}

void PrintOutdoorAuditFeature(std::string const & event, std::string const & source, FeatureType & feature,
                              double distanceMeters = -1.0)
{
  OutdoorFeatureAuditRecord record;
  record.m_event = event;
  record.m_source = source;
  record.m_feature = feature.GetID().m_index;
  record.m_geometry = feature.GetGeomType() == feature::GeomType::Point ? "point"
                    : feature.GetGeomType() == feature::GeomType::Line  ? "line"
                                                                        : "area";
  feature.ForEachName([&](int8_t, std::string_view name) { record.m_names.emplace_back(name); });
  feature.ForEachType([&](uint32_t type) { record.m_types.push_back(classif().GetReadableObjectName(type)); });
  auto const position = mercator::ToLatLon(feature::GetCenter(feature, FeatureType::BEST_GEOMETRY));
  record.m_latitude = position.m_lat;
  record.m_longitude = position.m_lon;
  record.m_distanceMeters = distanceMeters;
  std::string json;
  TEST(!glz::write_json(record, json), (source, record.m_feature));
  std::cout << "MIKSHAT_FEATURE_AUDIT " << json << '\n';
}
}  // namespace

UNIT_TEST(MikshatOutdoor_ActualFeatureClassificationAudit)
{
  classificator::Load();
  char const * directory = std::getenv("MIKSHAT_SUPPLEMENTARY_MAPS_DIR");
  TEST(directory && *directory, ("Supply all four actual bundled maps"));
  std::vector<std::string> paths;
  for (std::string const name : {"desert-ksa-north", "desert-ksa-south", "desert-kuwait", "desert-qatar"})
    paths.push_back(std::string(directory) + "/" + name + ".mwm");
  for (auto const key : {"MIKSHAT_SAUDI_NORTH_MWM_PATH", "MIKSHAT_SAUDI_SOUTH_MWM_PATH"})
    if (char const * path = std::getenv(key); path && *path)
      paths.emplace_back(path);

  std::array<std::string, 4> const terms = {NormalizeOutdoorAuditName("خصام"), NormalizeOutdoorAuditName("مشرف"),
                                            NormalizeOutdoorAuditName("الأمغر"), NormalizeOutdoorAuditName("حشمة")};
  static ftypes::BaseCheckerEx const sandy(
      {{"natural", "beach", "sand"}, {"natural", "desert"}, {"natural", "peak"}, {"natural", "hill"}});
  static ftypes::BaseCheckerEx const protectedAreas(
      {{"boundary", "national_park"}, {"boundary", "protected_area"}, {"leisure", "nature_reserve"}});
  static ftypes::BaseCheckerEx const roads({{"highway"}});
  auto const reportedRoad = mercator::FromLatLon(28.0 + 0.628 / 60.0, 42.0 + 0.426 / 60.0);
  auto const roadViewport = mercator::RectByCenterXYAndSizeInMeters(reportedRoad, 2000.0);
  size_t totalFeatures = 0;
  size_t totalMatches = 0;
  size_t totalRoads = 0;
  for (auto const & path : paths)
  {
    FeaturesFetcher source;
    auto file = platform::LocalCountryFile::MakeTemporary(path);
    file.SyncWithDisk();
    auto const registered = source.RegisterMap(file);
    TEST_EQUAL(registered.second, MwmSet::RegResult::Success, (path));
    FeaturesLoaderGuard loader(source.GetDataSource(), registered.first);
    auto const count = loader.GetNumFeatures();
    TEST_GREATER(count, 0, (path));
    totalFeatures += count;
    std::map<std::string, size_t> categories;
    size_t sandySamples = 0;
    size_t protectedSamples = 0;
    size_t matches = 0;
    for (uint32_t index = 0; index < count; ++index)
    {
      auto feature = loader.GetFeatureByIndex(index);
      bool matched = false;
      feature->ForEachName([&](int8_t, std::string_view name)
      {
        auto const normalized = NormalizeOutdoorAuditName(name);
        matched = matched || std::any_of(terms.begin(), terms.end(),
                                         [&](auto const & term) { return normalized.find(term) != std::string::npos; });
      });
      if (matched)
      {
        PrintOutdoorAuditFeature("requested-name", file.GetCountryName(), *feature);
        ++matches;
      }
      if (sandy(*feature))
      {
        feature->ForEachType([&](uint32_t type) { ++categories[classif().GetReadableObjectName(type)]; });
        if (feature->HasName() && sandySamples++ < 3)
          PrintOutdoorAuditFeature("sandy-sample", file.GetCountryName(), *feature);
      }
      if (protectedAreas(*feature) && protectedSamples++ < 3)
        PrintOutdoorAuditFeature("protected-sample", file.GetCountryName(), *feature);
    }
    totalMatches += matches;
    std::vector<std::pair<double, uint32_t>> closestRoads;
    source.GetDataSource().ForEachInRectForMWM([&](FeatureType & feature)
    {
      if (feature.GetGeomType() != feature::GeomType::Line || !roads(feature))
        return;
      double const distance = feature::GetMinDistanceMeters(feature, reportedRoad, FeatureType::BEST_GEOMETRY);
      if (distance <= 2000.0)
        closestRoads.emplace_back(distance, feature.GetID().m_index);
    }, roadViewport, 17, registered.first);
    std::sort(closestRoads.begin(), closestRoads.end());
    totalRoads += closestRoads.size();
    if (closestRoads.size() > 12)
      closestRoads.resize(12);
    for (auto const & [distance, index] : closestRoads)
    {
      auto feature = loader.GetFeatureByIndex(index);
      PrintOutdoorAuditFeature("reported-road-nearby", file.GetCountryName(), *feature, distance);
    }
    std::string categoryJson;
    TEST(!glz::write_json(categories, categoryJson), (path));
    std::cout << "MIKSHAT_FEATURE_AUDIT_SUMMARY {\"source\":\"" << file.GetCountryName() << "\",\"features\":" << count
              << ",\"requestedNameMatches\":" << matches << ",\"nearbyRoads\":" << closestRoads.size()
              << ",\"sandyTypes\":" << categoryJson << "}\n";
  }
  TEST_GREATER(totalFeatures, 0, ());
  std::cout << "MIKSHAT_FEATURE_AUDIT_COMPLETE {\"maps\":" << paths.size() << ",\"features\":" << totalFeatures
            << ",\"requestedNameMatches\":" << totalMatches << ",\"nearbyRoads\":" << totalRoads << "}" << std::endl;
}

UNIT_TEST(MikshatOutdoor_ActualLocalitiesAndReportedTrack)
{
  InitTransliterationInstanceWithDefaultDirs();
  classificator::Load();
  std::array<MapStyle, 6> const styles = {MapStyleDefaultLight, MapStyleDefaultDark,   MapStyleVehicleLight,
                                          MapStyleVehicleDark,  MapStyleOutdoorsLight, MapStyleOutdoorsDark};
  for (auto const style : styles)
    classificator::EnsureStyleLoaded(style);
  auto const arabic = StringUtf8Multilang::GetLangIndex("ar");

  char const * directory = std::getenv("MIKSHAT_SUPPLEMENTARY_MAPS_DIR");
  char const * officialNorth = std::getenv("MIKSHAT_SAUDI_NORTH_MWM_PATH");
  char const * officialSouth = std::getenv("MIKSHAT_SAUDI_SOUTH_MWM_PATH");
  TEST(directory && *directory && officialNorth && *officialNorth && officialSouth && *officialSouth,
       ("The real supplementary and both verified official fixtures are required"));
  std::array<std::string, 4> const names = {"خب أبو خصام", "طعس مشرف", "الأمغر", "خب حشمة"};
  std::array<uint32_t, 4> const supplementaryIndices = {17844, 17877, 17886, 17896};
  std::array<ms::LatLon, 4> const officialLocations = {{{28.6001633474, 41.3101644912},
                                                        {28.6177791034, 41.2874998248},
                                                        {28.6294428236, 41.3394434850},
                                                        {28.7150892686, 41.3658739728}}};
  std::array<std::string, 2> const paths = {std::string(directory) + "/desert-ksa-north.mwm", officialNorth};
  size_t checked = 0;
  uint32_t reportedTrack = 0;
  for (size_t map = 0; map < paths.size(); ++map)
  {
    FeaturesFetcher source;
    auto file = platform::LocalCountryFile::MakeTemporary(paths[map]);
    file.SyncWithDisk();
    auto const registered = source.RegisterMap(file);
    TEST_EQUAL(registered.second, MwmSet::RegResult::Success, (paths[map]));
    FeaturesLoaderGuard loader(source.GetDataSource(), registered.first);
    for (size_t named = 0; named < names.size(); ++named)
    {
      auto const index = map == 0
                           ? supplementaryIndices[named]
                           : FindNamedFeature(source, registered.first, names[named], officialLocations[named],
                                              classif().GetTypeByPath({"place", "locality"}), feature::GeomType::Point);
      auto feature = loader.GetFeatureByIndex(index);
      bool sameName = false;
      feature->ForEachName([&](int8_t, std::string_view name)
      { sameName = sameName || NormalizeOutdoorAuditName(name) == NormalizeOutdoorAuditName(names[named]); });
      TEST(sameName, (file.GetCountryName(), names[named]));
      TEST_EQUAL(feature->GetGeomType(), feature::GeomType::Point, ());
      TEST(feature::TypesHolder(*feature).Has(classif().GetTypeByPath({"place", "locality"})), ());
      TEST_EQUAL(feature::GetMikshatOutdoorFeatureVisibility(*feature), feature::kMikshatSandyVisibility, ());
      auto const rect = mercator::RectByCenterXYAndSizeInMeters(feature->GetCenter(), 8000.0);
      for (int const scale : {9, 10, 14})
      {
        std::vector<FeatureID> ids;
        source.ForEachFeatureIDForRendering(rect, [&](auto const & id) { ids.push_back(id); }, scale, {},
                                            feature::GetMikshatOutdoorVisibility(15000.0));
        TEST(std::find(ids.begin(), ids.end(), feature->GetID()) != ids.end(),
             ("Every real named locality must be available at the same 15 km policy", map, named, scale));
        for (auto const style : styles)
        {
          df::Stylist const visible(*feature, scale, arabic, style, feature::GetMikshatOutdoorVisibility(15000.0));
          TEST(visible.m_captionRule && visible.m_captionRule->primary, (map, named, scale, style));
          TEST_EQUAL(visible.m_captionRule->primary->color & 0xFFFFFF, 0, (map, named, scale, style));
          TEST_GREATER_OR_EQUAL(visible.m_captionRule->primary->height, 14, (map, named, scale, style));
          TEST(!visible.m_captionDescriptor.GetMainText().empty(), (map, named, scale, style));
          df::Stylist const hidden(*feature, scale, arabic, style, feature::GetMikshatOutdoorVisibility(20000.0));
          TEST(!hidden.m_captionRule,
               ("The same category stays hidden outside its 15 km threshold", map, named, style));
        }
      }
      ++checked;
    }
    if (map == 0)
    {
      // An identically named hamlet elsewhere is a settlement, not this locality category.
      auto hamlet = loader.GetFeatureByIndex(15632);
      TEST(feature::TypesHolder(*hamlet).Has(classif().GetTypeByPath({"place", "hamlet"})), ());
      TEST_EQUAL(feature::GetMikshatOutdoorFeatureVisibility(*hamlet), 0, ());
    }
    else
    {
      reportedTrack = FindReportedTrack(source, registered.first);
      auto road = loader.GetFeatureByIndex(reportedTrack);
      TEST(feature::TypesHolder(*road).Has(classif().GetTypeByPath({"highway", "track"})), ());
      TEST(ftypes::IsUnpavedRoad(feature::TypesHolder(*road)), ());
      TEST_EQUAL(feature::GetMikshatOutdoorFeatureVisibility(*road), feature::kMikshatOutdoorVisibility, ());
      auto const reportedPoint = mercator::FromLatLon(28.0 + 0.628 / 60.0, 42.0 + 0.426 / 60.0);
      TEST_LESS(feature::GetMinDistanceMeters(*road, reportedPoint, FeatureType::BEST_GEOMETRY), 50.0, ());
      for (auto const style : styles)
      {
        for (int const scale : {9, 14, 17})
        {
          df::Stylist const track(*road, scale, arabic, style, feature::GetMikshatOutdoorVisibility(20000.0));
          TEST(!track.m_lineRules.empty(), (style, scale));
          for (auto const line : track.m_lineRules)
            TEST(!line->dashdot, ("The actual reported track must be solid", style, scale));
        }
      }
    }
  }

  FeaturesFetcher southSource;
  auto southFile = platform::LocalCountryFile::MakeTemporary(officialSouth);
  southFile.SyncWithDisk();
  auto const south = southSource.RegisterMap(southFile);
  TEST_EQUAL(south.second, MwmSet::RegResult::Success, ());
  FeaturesLoaderGuard southLoader(southSource.GetDataSource(), south.first);
  auto const faydaIndex = FindNamedFeature(southSource, south.first, "فيضة الخويش", {25.3479422061, 47.2901334412},
                                           classif().GetTypeByPath({"place", "locality"}), feature::GeomType::Point);
  auto fayda = southLoader.GetFeatureByIndex(faydaIndex);
  TEST(ftypes::IsNamedFayda(*fayda), ());
  TEST_EQUAL(feature::GetMikshatOutdoorFeatureVisibility(*fayda), feature::kMikshatOutdoorVisibility, ());
  TEST_EQUAL(checked, 8, ("All four actual examples in both map sources must be verified"));
  std::cout << "MIKSHAT_REAL_LOCALITY_POLICY {\"sources\":2,\"namedLandmarks\":" << checked
            << ",\"reportedTrack\":" << reportedTrack << ",\"hamletControl\":15632,\"faydaControl\":" << faydaIndex
            << "}" << std::endl;
}

UNIT_TEST(MikshatOutdoor_ActualProtectedAreasAcrossSources)
{
  InitTransliterationInstanceWithDefaultDirs();
  classificator::Load();
  std::array<MapStyle, 6> const styles = {MapStyleDefaultLight, MapStyleDefaultDark,   MapStyleVehicleLight,
                                          MapStyleVehicleDark,  MapStyleOutdoorsLight, MapStyleOutdoorsDark};
  for (auto const style : styles)
    classificator::EnsureStyleLoaded(style);
  char const * directory = std::getenv("MIKSHAT_SUPPLEMENTARY_MAPS_DIR");
  char const * officialNorth = std::getenv("MIKSHAT_SAUDI_NORTH_MWM_PATH");
  char const * officialSouth = std::getenv("MIKSHAT_SAUDI_SOUTH_MWM_PATH");
  TEST(directory && *directory && officialNorth && *officialNorth && officialSouth && *officialSouth,
       ("Actual protected-area coverage is required from both map sources"));
  auto const arabic = StringUtf8Multilang::GetLangIndex("ar");
  std::array<std::string, 4> const paths = {std::string(directory) + "/desert-ksa-north.mwm",
                                            std::string(directory) + "/desert-ksa-south.mwm", officialNorth,
                                            officialSouth};
  std::array<uint32_t, 2> const supplementaryAreas = {36786, 28626};
  std::array<std::string, 2> const officialNames = {"محمية الأمير محمد بن سلمان الملكية", "محمية جزر فرسان"};
  std::array<ms::LatLon, 2> const officialLocations = {
      {{27.0353257466, 36.3903064757}, {16.7586886391, 41.8749974808}}};
  for (size_t map = 0; map < paths.size(); ++map)
  {
    FeaturesFetcher source;
    auto file = platform::LocalCountryFile::MakeTemporary(paths[map]);
    file.SyncWithDisk();
    auto const registered = source.RegisterMap(file);
    TEST_EQUAL(registered.second, MwmSet::RegResult::Success, (paths[map]));
    FeaturesLoaderGuard loader(source.GetDataSource(), registered.first);
    uint32_t const areaIndex =
        map < 2 ? supplementaryAreas[map]
                : FindNamedFeature(source, registered.first, officialNames[map - 2], officialLocations[map - 2],
                                   classif().GetTypeByPath({"leisure", "nature_reserve"}), feature::GeomType::Area,
                                   20000.0);
    auto area = loader.GetFeatureByIndex(areaIndex);
    TEST_EQUAL(area->GetGeomType(), feature::GeomType::Area, (map));
    TEST(area->HasName(), (map));
    TEST_EQUAL(feature::GetMikshatOutdoorFeatureVisibility(*area), feature::kMikshatProtectedVisibility, (map));
    bool foundTriangle = false;
    m2::PointD interior;
    area->ForEachTriangle([&](auto const & a, auto const & b, auto const & c)
    {
      if (!foundTriangle)
        interior = (a + b + c) / 3.0;
      foundTriangle = true;
    }, FeatureType::BEST_GEOMETRY);
    TEST(foundTriangle, ("The actual area must have filled geometry", map));
    auto const rect = mercator::RectByCenterXYAndSizeInMeters(interior, 15000.0);
    for (int const scale : {6, 7, 8})
    {
      std::vector<FeatureID> ids;
      source.ForEachFeatureIDForRendering(rect, [&](auto const & id) { ids.push_back(id); }, scale, {},
                                          feature::GetMikshatOutdoorVisibility(50000.0));
      TEST(std::find(ids.begin(), ids.end(), area->GetID()) != ids.end(),
           ("The 50 km protected policy must return pure areas, not only separate line records", map, scale));
      auto rendered = loader.GetFeatureByIndex(areaIndex);
      feature::PrepareMikshatOverviewGeometry(*rendered, scale);
      TEST(!rendered->IsEmptyGeometry(scale), (map, scale));
      for (auto const style : styles)
      {
        df::Stylist const visible(*rendered, scale, arabic, style, feature::GetMikshatOutdoorVisibility(50000.0));
        TEST(visible.m_captionRule && visible.m_captionRule->primary, (map, scale, style));
        TEST(!visible.m_captionDescriptor.GetMainText().empty(), (map, scale, style));
        TEST(visible.m_areaRule || visible.m_hatchingRule, (map, scale, style));
        TEST(visible.m_isProtectedAreaFill || visible.m_isProtectedAreaHatching, (map, scale, style));
        TEST(!visible.m_areaOutlineRules.empty(),
             ("The outline must be independent of its suppressible fill", map, scale, style));
        for (auto const border : visible.m_areaOutlineRules)
        {
          TEST_EQUAL(border->color & 0xFFFFFF, MapStyleIsDark(style) ? 0xBE97DF : 0x8557AC, (map, style));
          TEST(!border->dashdot, (map, style));
        }
        df::Stylist const hidden(*rendered, scale, arabic, style, feature::GetMikshatOutdoorVisibility(100000.0));
        TEST(!hidden.m_captionRule && !hidden.m_areaRule && !hidden.m_hatchingRule && hidden.m_areaOutlineRules.empty(),
             ("Names, boundaries and fill share the same outer 50 km threshold", map, scale, style));
      }
    }
    for (auto const style : styles)
    {
      df::Stylist const broad(*area, 8, arabic, style, feature::GetMikshatOutdoorVisibility(50000.0));
      df::Stylist const closer(*area, 14, arabic, style, feature::GetMikshatOutdoorVisibility(2000.0));
      df::Stylist const detail(*area, 17, arabic, style, feature::GetMikshatOutdoorVisibility(200.0));
      TEST(
          !broad.m_areaOutlineRules.empty() && !closer.m_areaOutlineRules.empty() && !detail.m_areaOutlineRules.empty(),
          (map, style));
      TEST_GREATER(closer.m_areaOutlineRules.front()->width, broad.m_areaOutlineRules.front()->width, (map, style));
      TEST_GREATER(detail.m_areaOutlineRules.front()->width, closer.m_areaOutlineRules.front()->width, (map, style));
      TEST(closer.m_captionRule && detail.m_captionRule, ("Names remain at the fill cutoff and closer", map, style));
    }
  }
  std::cout << "MIKSHAT_REAL_PROTECTED_POLICY {\"sources\":4,\"areaFeatures\":4,\"overviewDrawScales\":[6,7,8]}"
            << std::endl;
}

UNIT_TEST(MikshatOverview_SupplementaryOutdoorGeometry)
{
  classificator::Load();
  char const * directory = std::getenv("MIKSHAT_SUPPLEMENTARY_MAPS_DIR");
  TEST(directory && *directory, ("Supply the four actual bundled supplementary maps"));
  FeaturesFetcher source;
  size_t checkedLines = 0;
  size_t checkedAreas = 0;
  size_t checkedWadis = 0;
  size_t checkedTracks = 0;
  static ftypes::BaseCheckerEx const wadis({{"waterway", "river"}, {"waterway", "stream"}});
  static ftypes::BaseCheckerEx const tracks({{"highway", "track"}});
  for (std::string const name : {"desert-ksa-north", "desert-ksa-south", "desert-kuwait", "desert-qatar"})
  {
    auto file = platform::LocalCountryFile::MakeTemporary(std::string(directory) + "/" + name + ".mwm");
    file.SyncWithDisk();
    auto const registered = source.RegisterMap(file);
    TEST_EQUAL(registered.second, MwmSet::RegResult::Success, (name));
    FeaturesLoaderGuard loader(source.GetDataSource(), registered.first);
    std::vector<uint32_t> samples;
    std::array<bool, 3> found = {};
    for (uint32_t i = 0; i < loader.GetNumFeatures(); ++i)
    {
      auto f = loader.GetFeatureByIndex(i);
      if (!feature::IsMikshatOverviewGeometry(*f))
        continue;
      bool const line = f->GetGeomType() == feature::GeomType::Line;
      if (line && !wadis(*f) && !tracks(*f))
        continue;
      size_t const kind = line ? (wadis(*f) ? 0 : 1) : 2;
      if (found[kind])
        continue;
      samples.push_back(i);
      found[kind] = true;
      if (std::all_of(found.begin(), found.end(), [](bool value) { return value; }))
        break;
    }
    for (uint32_t const index : samples)
    {
      auto original = loader.GetFeatureByIndex(index);
      auto const expectedRect = original->GetLimitRect(FeatureType::BEST_GEOMETRY);
      bool const line = original->GetGeomType() == feature::GeomType::Line;
      auto const checkGeometry = [&](int scale)
      {
        // Keep each map's native simplification where it exists. Only missing
        // overview geometry needs the authentic highest-detail fallback.
        auto expected = loader.GetFeatureByIndex(index);
        bool const needsFallback = expected->IsEmptyGeometry(scale);
        if (needsFallback)
        {
          expected->ResetGeometry();
          expected->GetLimitRect(FeatureType::BEST_GEOMETRY);
        }
        auto rendered = loader.GetFeatureByIndex(index);
        feature::PrepareMikshatOverviewGeometry(*rendered, scale);
        TEST(!rendered->IsEmptyGeometry(scale), (name, index, scale));
        TEST_EQUAL(rendered->GetLimitRect(scale), expected->GetLimitRect(scale),
                   ("Preserve available native geometry and only fill missing detail", name, index, scale));
        std::vector<m2::PointD> expectedVertices;
        std::vector<m2::PointD> renderedVertices;
        auto const readVertices = [scale](FeatureType & f, std::vector<m2::PointD> & vertices)
        {
          f.ForEachPoint([&](auto const & point) { vertices.push_back(point); }, scale);
          f.ForEachTriangle([&](auto const & a, auto const & b, auto const & c)
          {
            vertices.push_back(a);
            vertices.push_back(b);
            vertices.push_back(c);
          }, scale);
        };
        readVertices(*expected, expectedVertices);
        readVertices(*rendered, renderedVertices);
        TEST(!renderedVertices.empty(), (name, index, scale));
        TEST_EQUAL(renderedVertices, expectedVertices, (name, index, scale, needsFallback));
      };
      auto center = expectedRect.Center();
      if (line)
        center = original->GetPoint(0);
      else
      {
        bool first = true;
        original->ForEachTriangle([&](auto const & a, auto const &, auto const &)
        {
          if (first)
            center = a;
          first = false;
        }, FeatureType::BEST_GEOMETRY);
      }
      auto const rect = mercator::RectByCenterXYAndSizeInMeters(center, 20000.0);
      for (int const scale : {9, 10})
      {
        auto const ids = ReadOverviewIds(source, rect, scale, true);
        TEST(std::binary_search(ids.begin(), ids.end(), original->GetID()), (name, index, scale));
        checkGeometry(scale);
      }
      checkGeometry(14);
      auto nativeDetail = loader.GetFeatureByIndex(index);
      TEST(!nativeDetail->IsEmptyGeometry(15), ("Native geometry must exist after the supplement ends", name, index));
      if (line)
      {
        TEST_GREATER(nativeDetail->GetPointsCount(), 1, (name, index));
        (wadis(*original) ? checkedWadis : checkedTracks)++;
      }
      auto const nativeIds = ReadOverviewIds(source, rect, 15, false);
      TEST(std::binary_search(nativeIds.begin(), nativeIds.end(), original->GetID()),
           ("Native index must take over at detail zoom 15", name, index));
      (line ? checkedLines : checkedAreas)++;
    }
    std::cout << "MIKSHAT_SUPPLEMENTARY_OVERVIEW " << name << " samples=" << samples.size() << '\n';
  }
  TEST_GREATER(checkedLines, 0, ("Actual reference map line geometry must be exercised"));
  TEST_GREATER(checkedWadis, 0, ("Actual wadis must be shown in the reference map overview"));
  TEST_GREATER(checkedTracks, 0, ("Actual dirt tracks must be shown in the reference map overview"));
  std::cout << "MIKSHAT_SUPPLEMENTARY_OVERVIEW lines=" << checkedLines << " areas=" << checkedAreas << std::endl;
}
#endif  // MIKSHAT_SUPPLEMENTARY_OVERVIEW_TESTS
}  // namespace mwm_index_test
