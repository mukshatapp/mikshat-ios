#include "testing/testing.hpp"

#include "drape_frontend/stylist.hpp"

#include "indexer/classificator.hpp"
#include "indexer/classificator_loader.hpp"
#include "indexer/drules_selector.hpp"
#include "indexer/feature.hpp"
#include "indexer/feature_visibility.hpp"
#include "indexer/map_object.hpp"
#include "indexer/map_style_reader.hpp"
#include "indexer/mikshat_map_visibility.hpp"
#include "indexer/mwm_set.hpp"
#include "indexer/transliteration_loader.hpp"

#include "drape/hatching_decl.hpp"

#include <algorithm>
#include <array>
#include <initializer_list>
#include <memory>

namespace
{
auto constexpr kStyles = []
{
  std::array<MapStyle, MapStyleCount - 1> styles{};
  for (size_t i = 0, s = 0; s < MapStyleCount; ++s)
    if (auto const style = static_cast<MapStyle>(s); style != MapStyleMerged)
      styles[i++] = style;
  return styles;
}();

class WaterArea : public osm::MapObject
{
public:
  explicit WaterArea(std::initializer_list<uint32_t> types)
  {
    m_geomType = feature::GeomType::Area;
    m_triangles = {{0.0, 0.0}, {0.01, 0.0}, {0.0, 0.01}};
    for (auto type : types)
      m_types.Add(type);
  }
};

class SampleFeature : public osm::MapObject
{
public:
  SampleFeature(uint32_t type, feature::GeomType geomType)
  {
    m_geomType = geomType;
    m_points = {{0.0, 0.0}, {0.01, 0.01}};
    m_triangles = {{0.0, 0.0}, {0.01, 0.0}, {0.0, 0.01}};
    m_types.Add(type);
    m_name.Add("en", "Sample");
    m_houseNumber = "12";
  }
};

class StyleSnapshotFixture
{
public:
  StyleSnapshotFixture() : m_originalStyle(GetStyleReader().GetCurrentStyle())
  {
    InitTransliterationInstanceWithDefaultDirs();
    classificator::Load();
    for (auto const style : kStyles)
      classificator::EnsureStyleLoaded(style);
  }

  ~StyleSnapshotFixture() { GetStyleReader().SetCurrentStyle(m_originalStyle); }

private:
  MapStyle const m_originalStyle;
};

class NamedLocality : public osm::MapObject
{
  class LocalityMapInfo : public MwmInfo
  {
  public:
    LocalityMapInfo()
    {
      m_minScale = 9;
      m_maxScale = 17;
      m_data.SetLanguages({"ar"});
    }
  };

public:
  explicit NamedLocality(std::string_view name)
  {
    // CaptionDescription resolves readable names through the feature's map.
    // A detached synthetic feature would correctly have its caption cleared.
    m_featureID = FeatureID(MwmSet::MwmId(std::make_shared<LocalityMapInfo>()), 0);
    m_geomType = feature::GeomType::Point;
    m_points = {{0.0, 0.0}};
    m_types.Add(classif().GetTypeByPath({"place", "locality"}));
    m_name.Add("default", name);
    m_name.Add("ar", name);
  }
};

class SurfaceRoad : public osm::MapObject
{
public:
  SurfaceRoad(std::string_view highway, std::string_view surface)
  {
    m_geomType = feature::GeomType::Line;
    m_points = {{0.0, 0.0}, {0.01, 0.01}};
    m_types.Add(classif().GetTypeByPath({"highway", highway}));
    if (!surface.empty())
      m_types.Add(classif().GetTypeByPath({"psurface", surface}));
    m_name.Add("en", "Road");
  }
};

void TestSameRules(df::Stylist const & actual, df::Stylist const & expected)
{
  TEST_EQUAL(actual.m_symbolRule, expected.m_symbolRule, ());
  TEST_EQUAL(actual.m_captionRule, expected.m_captionRule, ());
  TEST_EQUAL(actual.m_houseNumberRule, expected.m_houseNumberRule, ());
  TEST_EQUAL(actual.m_pathtextRule, expected.m_pathtextRule, ());
  TEST_EQUAL(actual.m_shieldRule, expected.m_shieldRule, ());
  TEST_EQUAL(actual.m_areaRule, expected.m_areaRule, ());
  TEST_EQUAL(actual.m_isProtectedAreaFill, expected.m_isProtectedAreaFill, ());
  TEST_EQUAL(actual.m_isProtectedAreaHatching, expected.m_isProtectedAreaHatching, ());
  TEST_EQUAL(actual.m_hatchingPattern, expected.m_hatchingPattern, ());
  TEST_EQUAL(actual.m_hatchingRule, expected.m_hatchingRule, ());
  TEST(std::equal(actual.m_lineRules.begin(), actual.m_lineRules.end(), expected.m_lineRules.begin(),
                  expected.m_lineRules.end()),
       ());
  TEST(std::equal(actual.m_areaOutlineRules.begin(), actual.m_areaOutlineRules.end(),
                  expected.m_areaOutlineRules.begin(), expected.m_areaOutlineRules.end()),
       ());
}
}  // namespace

UNIT_CLASS_TEST(StyleSnapshotFixture, Stylist_MikshatNamedFayda)
{
  for (auto const style : kStyles)
  {
    uint32_t const green = MapStyleIsDark(style) ? 0x7AD49A : 0x207440;
    for (auto const name : {"فيضة الخويش", "فيضةالخويش", "Faydat al Khuwaysh"})
    {
      auto ft = FeatureType::CreateFromMapObject(NamedLocality(name));
      for (uint8_t const zoom : {9, 14})
      {
        df::Stylist const stylist(*ft, zoom, StringUtf8Multilang::kEnglishCode, style);
        TEST(stylist.m_captionRule && stylist.m_captionRule->primary, (style, zoom, name));
        TEST_EQUAL(stylist.m_captionRule->primary->color & 0xFFFFFF, green, (style, zoom, name));
      }
    }
    for (auto const name : {"مزرعة الخويش", "شعيب الفيضة", "الخويش"})
    {
      auto ft = FeatureType::CreateFromMapObject(NamedLocality(name));
      df::Stylist const overview(*ft, 9, StringUtf8Multilang::kEnglishCode, style);
      TEST(!overview.m_captionRule, (style, name));
      df::Stylist const detail(*ft, 14, StringUtf8Multilang::kEnglishCode, style);
      TEST(detail.m_captionRule && detail.m_captionRule->primary, (style, name));
      TEST_NOT_EQUAL(detail.m_captionRule->primary->color & 0xFFFFFF, green, (style, name));
    }
  }
}

UNIT_CLASS_TEST(StyleSnapshotFixture, Stylist_MikshatUnpavedRoads)
{
  auto const unpavedSelector = drule::ParseSelector("unpaved_road");
  TEST(unpavedSelector, ());
  for (auto const style : kStyles)
  {
    uint32_t const brown = MapStyleIsDark(style) ? 0xC79A66 : 0x635730;
    for (auto const highway : {"unclassified", "residential", "service", "secondary", "track"})
    {
      auto pavedFeature = FeatureType::CreateFromMapObject(SurfaceRoad(highway, "paved_good"));
      TEST(!unpavedSelector->Test(*pavedFeature, 17), (style, highway));
      df::Stylist const paved(*pavedFeature, 17, StringUtf8Multilang::kEnglishCode, style);
      TEST(!paved.m_lineRules.empty(), (style, highway));
      for (auto const surface : {"unpaved_good", "unpaved_bad"})
      {
        auto unpavedFeature = FeatureType::CreateFromMapObject(SurfaceRoad(highway, surface));
        TEST(unpavedSelector->Test(*unpavedFeature, 17), (style, highway, surface));
        df::Stylist const unpaved(*unpavedFeature, 17, StringUtf8Multilang::kEnglishCode, style);
        TEST_EQUAL(unpaved.m_lineRules.size(), paved.m_lineRules.size(), (style, highway, surface));
        size_t brownLines = 0;
        for (size_t i = 0; i < unpaved.m_lineRules.size(); ++i)
        {
          auto actual = *unpaved.m_lineRules[i];
          auto const & original = *paved.m_lineRules[i];
          if ((actual.color & 0xFFFFFF) == brown)
          {
            ++brownLines;
            // A paved track can share the reference brown RGB, but keeps its base opacity.
            TEST_NOT_EQUAL(original.color, actual.color, (style, highway, surface));
            TEST(!actual.dashdot, ("Dirt roads must be solid", style, highway, surface));
            actual.color = original.color;
            actual.dashdot = original.dashdot;
          }
          // Only the dirt mainline color and dash pattern change; keep widths and every casing.
          TEST(actual == original, (style, highway, surface, i));
        }
        TEST_EQUAL(brownLines, 1, (style, highway, surface));
      }
    }
    auto unknownTrackFeature = FeatureType::CreateFromMapObject(SurfaceRoad("track", ""));
    TEST(unpavedSelector->Test(*unknownTrackFeature, 17), (style));
    df::Stylist const unknownTrack(*unknownTrackFeature, 17, StringUtf8Multilang::kEnglishCode, style);
    TEST_EQUAL(unknownTrack.m_lineRules.size(), 1, (style));
    TEST_EQUAL(unknownTrack.m_lineRules.front()->color & 0xFFFFFF, brown, (style));
    TEST(!unknownTrack.m_lineRules.front()->dashdot, (style));
  }
}

UNIT_TEST(Stylist_IsHatching)
{
  classificator::Load();
  auto const & cl = classif();

  auto const & checker = df::IsHatchingTerritoryChecker::Instance();

  TEST(checker(cl.GetTypeByPath({"boundary", "protected_area", "1"})), ());
  TEST(checker(cl.GetTypeByPath({"boundary", "protected_area", "2"})), ());
  TEST(checker(cl.GetTypeByPath({"boundary", "protected_area"})), ());

  TEST(checker(cl.GetTypeByPath({"boundary", "national_park"})), ());

  TEST(checker(cl.GetTypeByPath({"landuse", "military", "danger_area"})), ());

  TEST(checker(cl.GetTypeByPath({"amenity", "prison"})), ());
}

UNIT_TEST(Stylist_ProtectedAreaClassification)
{
  classificator::Load();
  auto const & cl = classif();
  auto const & checker = df::IsProtectedAreaChecker::Instance();
  TEST(checker(cl.GetTypeByPath({"boundary", "national_park"})), ());
  TEST(checker(cl.GetTypeByPath({"leisure", "nature_reserve"})), ());
  TEST(checker(cl.GetTypeByPath({"boundary", "protected_area"})), ());
  for (auto const protectClass : {"1", "2", "3", "4", "5", "6"})
  {
    TEST(checker(cl.GetTypeByPath({"boundary", "protected_area", protectClass})), (protectClass));
    TEST_EQUAL(df::IsHatchingTerritoryChecker::Instance().GetHatch(
                   cl.GetTypeByPath({"boundary", "protected_area", protectClass})),
               dp::k45dHatching, (protectClass));
  }

  for (auto const & path : {base::StringIL{"natural", "water"},
                            {"natural", "water", "intermittent"},
                            {"natural", "wetland"},
                            {"waterway", "river"},
                            {"landuse", "forest"},
                            {"landuse", "military"},
                            {"amenity", "prison"},
                            {"boundary", "aboriginal_lands"}})
    TEST(!checker(cl.GetTypeByPath(path)), (path));
}

UNIT_CLASS_TEST(StyleSnapshotFixture, ProtectedAreaFillRuleProvenance)
{
  for (auto const style : kStyles)
  {
    auto const & cl = classif(style);
    auto const protected1 = cl.GetTypeByPath({"boundary", "protected_area", "1"});
    auto const protected2 = cl.GetTypeByPath({"boundary", "protected_area", "2"});
    auto const wetland = cl.GetTypeByPath({"natural", "wetland"});
    for (auto const protectedType :
         {protected1, protected2, cl.GetTypeByPath({"boundary", "protected_area"}),
          cl.GetTypeByPath({"boundary", "protected_area", "3"}), cl.GetTypeByPath({"boundary", "protected_area", "4"}),
          cl.GetTypeByPath({"boundary", "protected_area", "5"}), cl.GetTypeByPath({"boundary", "protected_area", "6"}),
          cl.GetTypeByPath({"boundary", "national_park"}), cl.GetTypeByPath({"leisure", "nature_reserve"})})
      for (auto const base : {cl.GetTypeByPath({"natural", "water"}), cl.GetTypeByPath({"landuse", "forest"})})
      {
        auto feature = FeatureType::CreateFromMapObject(WaterArea({protectedType, base}));
        df::Stylist const stylist(*feature, 14, StringUtf8Multilang::kEnglishCode, style);
        TEST(stylist.m_areaRule != nullptr && stylist.m_hatchingRule != nullptr, (style));
        TEST(!stylist.m_isProtectedAreaFill,
             ("Water/forest must remain visible when protected hatching disappears", style));
        TEST(stylist.m_isProtectedAreaHatching, (style));
        TEST_EQUAL(stylist.m_hatchingPattern, dp::k45dHatching, (style));
      }

    auto feature = FeatureType::CreateFromMapObject(WaterArea({protected2, wetland}));
    df::Stylist const stylist(*feature, 14, StringUtf8Multilang::kEnglishCode, style);
    auto wetlandFeature = FeatureType::CreateFromMapObject(WaterArea({wetland}));
    df::Stylist const wetlandStyle(*wetlandFeature, 14, StringUtf8Multilang::kEnglishCode, style);
    TEST(stylist.m_hatchingRule != nullptr, (style));
    TEST_EQUAL(stylist.m_hatchingRule, wetlandStyle.m_hatchingRule, (style));
    TEST_EQUAL(stylist.m_hatchingPattern, dp::kDashHatching, (style));
    TEST(!stylist.m_isProtectedAreaFill, (style));
    TEST(!stylist.m_isProtectedAreaHatching,
         ("Wetland hatching must remain visible when protected fill disappears", style));
  }
}

UNIT_TEST(Stylist_IsAreaPattern)
{
  classificator::Load();
  auto const & cl = classif();

  // Constructing the singleton resolves every checker type via GetTypeByPath, which CHECKs the type
  // exists - so an invalid path (e.g. the 3-level natural=beach=sand mistaken for 2-level) fails here.
  auto const & checker = df::IsAreaPatternChecker::Instance();

  // Stipple: sandy / desert surfaces and intermittent water. natural=sand is a beach subtype, matched via the parent.
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"natural", "beach"})), dp::kStipplePattern, ());
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"natural", "beach", "sand"})), dp::kStipplePattern, ());
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"natural", "desert"})), dp::kStipplePattern, ());
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"natural", "water", "intermittent"})), dp::kStipplePattern, ());
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"landuse", "basin", "intermittent"})), dp::kStipplePattern, ());

  // Speckle: rocky surfaces.
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"natural", "scree"})), dp::kSpecklePattern, ());
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"natural", "bare_rock"})), dp::kSpecklePattern, ());

  // Grid: planted landuse.
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"landuse", "orchard"})), dp::kGridPattern, ());
  TEST_EQUAL(checker.GetPattern(cl.GetTypeByPath({"landuse", "vineyard"})), dp::kGridPattern, ());

  // Permanent water and unrelated area types get no pattern.
  TEST(checker.GetPattern(cl.GetTypeByPath({"natural", "water"})).empty(), ());
  TEST(checker.GetPattern(cl.GetTypeByPath({"landuse", "basin"})).empty(), ());
}

UNIT_TEST(Stylist_IntermittentWaterAreaPriority)
{
  auto & reader = GetStyleReader();
  for (size_t s = 0; s < MapStyleCount; ++s)
  {
    auto const style = static_cast<MapStyle>(s);
    if (style == MapStyleMerged)
      continue;
    reader.SetCurrentStyle(style);
    classificator::Load();
    auto const & cl = classif();
    auto const lake = cl.GetTypeByPath({"natural", "water", "lake"});
    auto const intermittent = cl.GetTypeByPath({"natural", "water", "intermittent"});
    auto const ditch = cl.GetTypeByPath({"natural", "water", "ditch"});
    auto const river = cl.GetTypeByPath({"waterway", "river"});
    auto const basin = cl.GetTypeByPath({"landuse", "basin"});
    auto const intermittentBasin = cl.GetTypeByPath({"landuse", "basin", "intermittent"});
    auto const areaPriority = [style](std::initializer_list<uint32_t> types, uint8_t zoom)
    {
      auto feature = FeatureType::CreateFromMapObject(WaterArea(types));
      df::Stylist stylist(*feature, zoom, StringUtf8Multilang::kEnglishCode, style);
      CHECK(stylist.m_areaRule != nullptr, ());
      return stylist.m_areaRule->priority;
    };

    auto const permanentDepthPriority = areaPriority({lake}, 14);
    auto const intermittentDepthPriority = areaPriority({lake, intermittent}, 14);
    auto const ditchDepthPriority = areaPriority({ditch, intermittent}, 14);
    drule::KeysT lineKeys;
    feature::GetDrawRule({river}, 14, feature::GeomType::Line, lineKeys);
    auto const line =
        std::find_if(lineKeys.begin(), lineKeys.end(), [](drule::Key const & k) { return k.m_type == drule::line; });
    CHECK(line != lineKeys.end(), ());
    // BG-top scales style priority by 0.1; gaps above 8 stay distinct even with a 16-bit depth buffer.
    TEST_GREATER(intermittentDepthPriority - line->m_priority, 8, (style));
    TEST_GREATER(permanentDepthPriority - intermittentDepthPriority, 8, (style));
    TEST_GREATER(ditchDepthPriority - permanentDepthPriority, 8, (style));
    TEST_EQUAL(areaPriority({ditch, intermittent}, 11), intermittentDepthPriority, (style));
    TEST_LESS(areaPriority({intermittentBasin}, 14), areaPriority({basin}, 14), (style));
  }
  reader.SetCurrentStyle(kDefaultMapStyle);
  classificator::Load();
}

UNIT_CLASS_TEST(StyleSnapshotFixture, Stylist_OutdoorRulerEligibilityPreservesOtherTypes)
{
  for (auto const style : kStyles)
  {
    auto const & cl = classif(style);
    auto const water = cl.GetTypeByPath({"natural", "water"});
    auto const protectedArea = cl.GetTypeByPath({"boundary", "protected_area", "2"});
    auto mixed = FeatureType::CreateFromMapObject(WaterArea({protectedArea, water}));
    auto waterOnly = FeatureType::CreateFromMapObject(WaterArea({water}));
    df::Stylist const protectedVisible(*mixed, 6, StringUtf8Multilang::kEnglishCode, style,
                                       feature::GetMikshatOutdoorVisibility(50000.0));
    TEST(protectedVisible.m_hatchingRule != nullptr, (style));
    TEST_EQUAL(protectedVisible.m_areaOutlineRules.size(), 1, ("Pure areas need a visible boundary", style));
    df::Stylist const hiddenProtected(*mixed, 6, StringUtf8Multilang::kEnglishCode, style,
                                      feature::GetMikshatOutdoorVisibility(100000.0));
    df::Stylist const baseWater(*waterOnly, 6, StringUtf8Multilang::kEnglishCode, style);
    TestSameRules(hiddenProtected, baseWater);

    auto sand = FeatureType::CreateFromMapObject(
        SampleFeature(cl.GetTypeByPath({"natural", "desert"}), feature::GeomType::Area));
    df::Stylist const namedSand(*sand, 9, StringUtf8Multilang::kEnglishCode, style,
                                feature::GetMikshatOutdoorVisibility(15000.0));
    df::Stylist const distantSand(*sand, 9, StringUtf8Multilang::kEnglishCode, style,
                                  feature::GetMikshatOutdoorVisibility(50000.0));
    TEST(namedSand.m_captionRule != nullptr, (style));
    TEST(distantSand.m_captionRule == nullptr, (style));
    TEST(namedSand.m_areaRule != nullptr && distantSand.m_areaRule != nullptr, (style));
    TEST_EQUAL(namedSand.m_areaRule, distantSand.m_areaRule,
               ("Sand ground remains visible beyond the label threshold", style));

    auto locality = FeatureType::CreateFromMapObject(NamedLocality("Generic locality without a terrain keyword"));
    df::Stylist const namedLocality(*locality, 9, StringUtf8Multilang::kEnglishCode, style,
                                    feature::GetMikshatOutdoorVisibility(15000.0));
    df::Stylist const distantLocality(*locality, 9, StringUtf8Multilang::kEnglishCode, style,
                                      feature::GetMikshatOutdoorVisibility(20000.0));
    TEST(namedLocality.m_captionRule && namedLocality.m_captionRule->primary, (style));
    TEST_EQUAL(namedLocality.m_captionRule->primary->color & 0xFFFFFF, 0, (style));
    TEST(distantLocality.m_captionRule == nullptr, (style));

    auto fayda = FeatureType::CreateFromMapObject(NamedLocality("فيضة الخويش"));
    df::Stylist const namedFayda(*fayda, 9, StringUtf8Multilang::kEnglishCode, style,
                                 feature::GetMikshatOutdoorVisibility(20000.0));
    TEST(namedFayda.m_captionRule && namedFayda.m_captionRule->primary, (style));
    TEST_EQUAL(namedFayda.m_captionRule->primary->color & 0xFFFFFF, MapStyleIsDark(style) ? 0x7AD49A : 0x207440,
               ("Faydas retain their own green, 20 km category", style));
    for (auto const & path : {base::StringIL{"place", "hamlet"}, {"natural", "peak"}})
    {
      auto other = FeatureType::CreateFromMapObject(SampleFeature(cl.GetTypeByPath(path), feature::GeomType::Point));
      df::Stylist const baseline(*other, 17, StringUtf8Multilang::kEnglishCode, style);
      df::Stylist const withoutOutdoorCategories(*other, 17, StringUtf8Multilang::kEnglishCode, style, 0);
      TestSameRules(withoutOutdoorCategories, baseline);
    }

    for (auto const & path : {base::StringIL{"waterway", "stream"}, {"highway", "track"}})
    {
      auto line = FeatureType::CreateFromMapObject(SampleFeature(cl.GetTypeByPath(path), feature::GeomType::Line));
      df::Stylist const visible(*line, 8, StringUtf8Multilang::kEnglishCode, style,
                                feature::GetMikshatOutdoorVisibility(20000.0));
      df::Stylist const hidden(*line, 8, StringUtf8Multilang::kEnglishCode, style,
                               feature::GetMikshatOutdoorVisibility(50000.0));
      TEST(!visible.m_lineRules.empty(), (style, path));
      TEST(hidden.m_lineRules.empty() && hidden.m_pathtextRule == nullptr, (style, path));
    }
  }
}

UNIT_CLASS_TEST(StyleSnapshotFixture, Stylist_ExplicitStyleIgnoresGlobalSwitches)
{
  using feature::GeomType;
  struct Sample
  {
    uint32_t m_type;
    GeomType m_geomType;
  };
  auto const & cl = classif(MapStyleDefaultLight);
  std::array const samples = {Sample{cl.GetTypeByPath({"highway", "motorway"}), GeomType::Line},
                              Sample{cl.GetTypeByPath({"highway", "path"}), GeomType::Line},
                              Sample{cl.GetTypeByPath({"amenity", "cafe"}), GeomType::Point},
                              Sample{cl.GetTypeByPath({"building"}), GeomType::Area},
                              Sample{cl.GetTypeByPath({"natural", "water", "lake"}), GeomType::Area}};

  for (auto const style : kStyles)
  {
    for (auto const & sample : samples)
    {
      auto feature = FeatureType::CreateFromMapObject(SampleFeature(sample.m_type, sample.m_geomType));
      bool hasRules = false;
      for (uint8_t zoom = 1; zoom <= 19; ++zoom)
      {
        GetStyleReader().SetCurrentStyle(style);
        df::Stylist const expected(*feature, zoom, StringUtf8Multilang::kEnglishCode, style);
        hasRules = hasRules || expected.m_symbolRule || expected.m_areaRule || !expected.m_lineRules.empty();
        for (auto const current : kStyles)
        {
          GetStyleReader().SetCurrentStyle(current);
          df::Stylist const actual(*feature, zoom, StringUtf8Multilang::kEnglishCode, style);
          TestSameRules(actual, expected);
        }
      }
      TEST(hasRules, (style, sample.m_type));
    }
  }
}
