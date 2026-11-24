#include "testing/testing.hpp"

#include "map/framework.hpp"

#include "indexer/classificator.hpp"
#include "indexer/classificator_loader.hpp"
#include "indexer/feature.hpp"
#include "indexer/ftypes_matcher.hpp"

#include "platform/local_country_file.hpp"
#include "platform/localization.hpp"

#include "coding/string_utf8_multilang.hpp"

#include "geometry/mercator.hpp"

#include <algorithm>
#include <memory>
#include <string_view>
#include <vector>

namespace
{
class DescriptorMapInfo : public MwmInfo
{
public:
  DescriptorMapInfo()
  {
    SetStatus(STATUS_REGISTERED);
    m_data.SetLanguages({"ar", "en"});
  }
};

class DescriptorFeature : public osm::MapObject
{
public:
  using osm::MapObject::GetLocalizedType;

  DescriptorFeature(base::StringIL const & type, std::string_view surface, std::string_view name = {},
                    feature::GeomType geometry = feature::GeomType::Line)
  {
    m_featureID = FeatureID(MwmSet::MwmId(std::make_shared<DescriptorMapInfo>()), 0);
    m_geomType = geometry;
    m_types = feature::TypesHolder(geometry);
    m_types.Add(classif().GetTypeByPath(type));
    if (!surface.empty())
      m_types.Add(classif().GetTypeByPath({"psurface", surface}));
    m_points = {{0.0, 0.0}, {0.01, 0.01}};
    m_triangles = {{0.0, 0.0}, {0.01, 0.0}, {0.0, 0.01}};
    for (auto const language : {"default", "ar", "en"})
      m_name.Add(language, name);
  }

  void AddType(base::StringIL const & type) { m_types.Add(classif().GetTypeByPath(type)); }
};
}  // namespace

UNIT_TEST(PlacePage_UnpavedRoadDescriptorPreservesNamesAndPavedRoads)
{
  classificator::Load();
  auto const dirtType = platform::GetLocalizedString("mikshat_dirt_road_type");
  for (auto const highway : {"track", "unclassified", "residential", "service", "secondary"})
  {
    auto const pavedType =
        platform::GetLocalizedTypeName(classif().GetReadableObjectName(classif().GetTypeByPath({"highway", highway})));
    for (auto const surface : {"unpaved_good", "unpaved_bad", "paved_good", "paved_bad"})
    {
      bool const unpaved = std::string_view(surface).starts_with("unpaved");
      for (auto const name : {"", "شارع الأمير عبد الله", "Named desert road"})
      {
        auto feature = FeatureType::CreateFromMapObject(DescriptorFeature({"highway", highway}, surface, name));
        place_page::Info info;
        info.SetFromFeatureType(*feature);
        auto const & category = unpaved ? dirtType : pavedType;
        if (std::string_view(name).empty())
        {
          TEST_EQUAL(info.GetTitle(), category, (highway, surface));
          TEST(info.GetSubtitle().find(dirtType) == std::string::npos, (highway, surface));
        }
        else
        {
          TEST_EQUAL(info.GetTitle(), name, (highway, surface));
          TEST_EQUAL(info.GetPrimaryFeatureName(), name, (highway, surface));
          TEST_EQUAL(info.GetSubtitle(), category, (highway, surface));
        }
      }
    }
    DescriptorFeature unknownSurface({"highway", highway}, "");
    TEST_EQUAL(unknownSurface.GetLocalizedType(), std::string_view(highway) == "track" ? dirtType : pavedType,
               (highway));
  }
}

UNIT_TEST(MapObject_UnpavedRoadDescriptorPreservesOtherCategories)
{
  classificator::Load();
  auto const dirtType = platform::GetLocalizedString("mikshat_dirt_road_type");
  for (auto const & type : {base::StringIL{"highway", "path"},
                            {"highway", "footway"},
                            {"man_made", "pier"},
                            {"amenity", "fuel"},
                            {"route", "ferry"}})
  {
    DescriptorFeature object(type, "unpaved_good");
    auto const original =
        platform::GetLocalizedTypeName(classif().GetReadableObjectName(classif().GetTypeByPath(type)));
    TEST_EQUAL(object.GetLocalizedType(), original, (type));
    TEST_EQUAL(object.GetLocalizedAllTypes(true), original, (type));
    TEST(object.GetLocalizedType() != dirtType, (type));
  }
  for (auto const geometry : {feature::GeomType::Point, feature::GeomType::Area})
  {
    DescriptorFeature object({"highway", "track"}, "unpaved_good", {}, geometry);
    TEST(!ftypes::IsUnpavedRoad(object.GetTypes()), (geometry));
    TEST(object.GetLocalizedType() != dirtType, (geometry));
  }
  DescriptorFeature contradictorySurface({"highway", "track"}, "unpaved_good");
  contradictorySurface.AddType({"psurface", "paved_bad"});
  TEST(!ftypes::IsUnpavedRoad(contradictorySurface.GetTypes()), ());
  TEST(contradictorySurface.GetLocalizedType() != dirtType, ());

  DescriptorFeature mixed({"highway", "track"}, "unpaved_good");
  mixed.AddType({"amenity", "fuel"});
  auto const fuelType =
      platform::GetLocalizedTypeName(classif().GetReadableObjectName(classif().GetTypeByPath({"amenity", "fuel"})));
  TEST(mixed.GetLocalizedAllTypes(true).find(fuelType) != std::string::npos, ());
}

UNIT_TEST(Framework_ForEachFeatureAtPoint_And_Others)
{
  using namespace std;

  Framework frm({} /* params */, false /* loadMaps */);
  frm.RegisterMap(platform::LocalCountryFile::MakeForTesting("minsk-pass"));

  // May vary according to the new minsk-pass data. The point is on the lift gate node, so that
  // all three ForEachFeatureAtPoint branches (Point, Line, Area) are covered.
  vector<char const *> types = {
      "highway|footway|",
      "psurface|paved_good|",

      "highway|service|parking_aisle|",
      "psurface|paved_good|",

      "landuse|retail|",

      "amenity|parking|private|",

      "barrier|lift_gate|",
  };
  frm.ForEachFeatureAtPoint([&](FeatureType & ft)
  {
    ft.ForEachType([&types](uint32_t type)
    {
      string const strType = classif().GetFullObjectName(type);
      auto found = find(types.begin(), types.end(), strType);
      TEST(found != types.end(), (strType));
      types.erase(found);
    });
  }, mercator::FromLatLon(53.8826401, 27.5378486), scales::GetUpperScale());
  TEST_EQUAL(0, types.size(), (types));

  ftypes::IsBuildingChecker const & isBuilding = ftypes::IsBuildingChecker::Instance();
  {
    // Restaurant in the building.
    auto const id = frm.GetFeatureAtPoint(mercator::FromLatLon(53.89395, 27.567365));
    TEST(id.IsValid(), ());
    frm.GetDataSource().ReadFeature([&](FeatureType & ft)
    {
      TEST_EQUAL("Родны Кут", ft.GetDefaultName(), ());
      TEST(!isBuilding(ft), ());
    }, id);
  }

  {
    // Same building as above, very close to the restaurant.
    auto const id = frm.GetFeatureAtPoint(mercator::FromLatLon(53.893603, 27.567032));
    TEST(id.IsValid(), ());
    frm.GetDataSource().ReadFeature([&](FeatureType & ft) { TEST(isBuilding(ft), ()); }, id);
  }
}
