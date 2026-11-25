#include "helpers.hpp"
#include "testing/testing.hpp"

#include "indexer/classificator.hpp"
#include "indexer/drawing_rules.hpp"
#include "indexer/feature.hpp"
#include "indexer/feature_data.hpp"
#include "indexer/feature_visibility.hpp"
#include "indexer/map_object.hpp"

#include "base/logging.hpp"
#include "base/stl_helpers.hpp"

namespace classificator_tests
{
using namespace std;

class DoCheckConsistency
{
  Classificator const & m_c;

public:
  explicit DoCheckConsistency(Classificator const & c) : m_c(c) {}
  void operator()(ClassifObject const * p, uint32_t type) const
  {
    if (p->IsDrawableAny() && !m_c.IsTypeValid(type))
      TEST(false, ("Inconsistency type", type, m_c.GetFullObjectName(type)));
  }
};

UNIT_TEST(Classificator_CheckConsistency)
{
  styles::RunForEveryMapStyle([](MapStyle)
  {
    Classificator const & c = classif();

    DoCheckConsistency doCheck(c);
    c.ForEachTree(doCheck);
  });
}

using namespace feature;

namespace
{

class DoCheckStyles
{
  Classificator const & m_c;
  GeomType m_geomType;
  int m_rules;

public:
  DoCheckStyles(Classificator const & c, GeomType geomType, int rules) : m_c(c), m_geomType(geomType), m_rules(rules) {}

  void operator()(ClassifObject const * p, uint32_t type) const
  {
    // We can't put TEST here, should check output manually. Or rewrite test in more sophisticated way.
    // - place=county/region are non-drawable
    // - historic=citywalls is not a Point
    // - waterway=* [tunnel] are non-drawable
    // - some highway,waterway are Point

    if (p->IsDrawableAny())
    {
      TypesHolder holder(m_geomType);
      holder.Add(type);

      pair<int, int> const range = GetDrawableScaleRangeForRules(holder, m_rules);
      if (range.first == -1 || range.second == -1)
        LOG(LWARNING, ("No styles:", m_c.GetFullObjectName(type)));
    }
    else if (ftype::GetLevel(type) > 1)
      LOG(LWARNING, ("Type without any rules:", m_c.GetFullObjectName(type)));
  }
};

void ForEachObject(Classificator const & c, vector<string_view> const & path, GeomType geomType, int rules)
{
  uint32_t const type = c.GetTypeByPath(path);
  ClassifObject const * pObj = c.GetObject(type);

  DoCheckStyles doCheck(c, geomType, rules);
  doCheck(pObj, type);
  pObj->ForEachObjectInTree(doCheck, type);
}

void ForEachObject(Classificator const & c, string const & name, GeomType geomType, int rules)
{
  ForEachObject(c, strings::Tokenize(name, "-"), geomType, rules);
}

void CheckPointStyles(Classificator const & c, string const & name)
{
  ForEachObject(c, name, GeomType::Point, RULE_CAPTION | RULE_SYMBOL);
}

void CheckLineStyles(Classificator const & c, string const & name)
{
  ForEachObject(c, name, GeomType::Line, RULE_PATH_TEXT);
}

}  // namespace

UNIT_TEST(Classificator_DrawingRules)
{
  styles::RunForEveryMapStyle([](MapStyle style)
  {
    if (style != MapStyle::MapStyleDefaultLight && style != MapStyle::MapStyleDefaultDark)
      return;

    Classificator const & c = classif();

    LOG(LINFO, ("--------------- Point styles ---------------"));
    CheckPointStyles(c, "amenity");
    CheckPointStyles(c, "historic");
    CheckPointStyles(c, "office");
    CheckPointStyles(c, "place");
    CheckPointStyles(c, "shop");
    CheckPointStyles(c, "sport");
    CheckPointStyles(c, "tourism");
    CheckPointStyles(c, "highway-bus_stop");
    CheckPointStyles(c, "highway-motorway_junction");
    CheckPointStyles(c, "railway-station");
    CheckPointStyles(c, "railway-tram_stop");
    CheckPointStyles(c, "railway-halt");

    LOG(LINFO, ("--------------- Linear styles ---------------"));
    CheckLineStyles(c, "highway");
    CheckLineStyles(c, "waterway");
    // CheckLineStyles(c, "railway");
  });
}

namespace
{

pair<int, int> GetMinMax(int level, vector<uint32_t> const & types, drule::TypeT ruleType)
{
  pair<int, int> res(numeric_limits<int>::max(), numeric_limits<int>::min());

  drule::KeysT keys;
  feature::GetDrawRule(types, level, feature::GeomType::Area, keys);

  for (size_t i = 0; i < keys.size(); ++i)
  {
    if (keys[i].m_type != ruleType)
      continue;

    if (keys[i].m_priority < res.first)
      res.first = keys[i].m_priority;
    if (keys[i].m_priority > res.second)
      res.second = keys[i].m_priority;
  }

  return res;
}

string CombineArrT(base::StringIL const & arrT)
{
  string result;
  for (auto it = arrT.begin(); it != arrT.end(); ++it)
  {
    if (it != arrT.begin())
      result.append("-");
    result.append(*it);
  }
  return result;
}

void CheckPriority(vector<base::StringIL> const & arrT, vector<size_t> const & arrI, drule::TypeT ruleType)
{
  Classificator const & c = classif();
  vector<vector<uint32_t>> types;
  vector<vector<string>> typesInfo;

  styles::RunForEveryMapStyle([&](MapStyle)
  {
    types.clear();
    typesInfo.clear();

    size_t ind = 0;
    for (size_t i = 0; i < arrI.size(); ++i)
    {
      types.push_back(vector<uint32_t>());
      types.back().reserve(arrI[i]);
      typesInfo.push_back(vector<string>());
      typesInfo.back().reserve(arrI[i]);

      for (size_t j = 0; j < arrI[i]; ++j)
      {
        types.back().push_back(c.GetTypeByPath(arrT[ind]));
        typesInfo.back().push_back(CombineArrT(arrT[ind]));
        ++ind;
      }
    }

    TEST_EQUAL(ind, arrT.size(), ());

    for (int level = scales::GetUpperWorldScale() + 1; level <= scales::GetUpperStyleScale(); ++level)
    {
      pair<int, int> minmax(numeric_limits<int>::max(), numeric_limits<int>::min());
      vector<string> minmaxInfo;
      for (size_t i = 0; i < types.size(); ++i)
      {
        pair<int, int> const mm = GetMinMax(level, types[i], ruleType);
        TEST_LESS(minmax.second, mm.first,
                  ("Priority bug on zoom", level, "group", i, ":", minmaxInfo, minmax.first, minmax.second, "vs",
                   typesInfo[i], mm.first, mm.second));
        minmax = mm;
        minmaxInfo = typesInfo[i];
      }
    }
  });
}

}  // namespace

// Check area drawing priority according to the types order below (from downmost to upmost).
// If someone disagrees with this order, please refer to VNG :)
// natural-coastline
// place-island = natural-land
// natural-scrub,heath,grassland = landuse-grass,farmland,forest
// natural-water,lake = landuse-basin

UNIT_TEST(Classificator_AreaPriority)
{
  CheckPriority(
      {// 0
       {"natural", "coastline"},
       // 1
       {"place", "island"},
       {"natural", "land"},
       // 2
       {"natural", "scrub"},
       {"natural", "heath"},
       {"natural", "grassland"},
       {"landuse", "grass"},
       {"landuse", "farmland"},
       {"landuse", "forest"},
       // ?
       //{"leisure", "park"}, {"leisure", "garden"}, - maybe next time (too tricky to do it now)
       // 3
       {"natural", "water"},
       {"natural", "water", "lake"},
       {"landuse", "basin"}},
      {1, 2, 6, 3}, drule::area);

  CheckPriority(
      {
          // ? - linear waterways @todo: add ability to compare different drule types (areas vs lines)
          //{"waterway", "river"}, {"waterway", "stream"}, {"natural", "strait"}, {"waterway", "ditch"},
          // 0 - intermittent water draws behind separate permanent water polygons.
          {"natural", "water", "intermittent"},
          {"landuse", "basin", "intermittent"},
          // 1 - permanent water areas
          {"natural", "water"},
          {"natural", "water", "basin"},
          {"natural", "water", "lake"},
          {"natural", "water", "lock"},
          {"natural", "water", "moat"},
          {"natural", "water", "pond"},
          {"natural", "water", "reservoir"},
          {"natural", "water", "river"},
          {"landuse", "basin"},
          {"landuse", "salt_pond"},
          {"waterway", "dock"},
          // 2 - water areas with their own look, also when intermittent
          {"natural", "water", "ditch"},
          {"natural", "water", "drain"},
          {"natural", "water", "wastewater"},
          // ? - hatching fills @todo: absent in vehicle style, need to test main style only
          //{"leisure", "nature_reserve"}, {"boundary", "national_park"}, {"landuse", "military"},
          // 3 - above-water features
          {"man_made", "pier"},
          {"man_made", "breakwater"},
          {"waterway", "dam"},
      },
      {2, 11, 3, 3}, drule::area);

  CheckPriority(
      {
          // 0
          {"leisure", "park"},
          // 1
          {"leisure", "pitch"},
          {"leisure", "playground"},
          {"sport", "multi"},
      },
      {1, 3}, drule::area);
}

UNIT_TEST(Classificator_PoiPriority)
{
  {
    CheckPriority(
        {
            // 1
            {"amenity", "drinking_water"},
            // 2
            {"tourism", "camp_site"},
            // 3
            {"tourism", "wilderness_hut"},
            // 4
            {"tourism", "alpine_hut"},
        },
        {1, 1, 1, 1}, drule::symbol);
  }
}

UNIT_TEST(Classificator_MultipleTypesPoiPriority)
{
  {
    CheckPriority(
        {// 1
         {"amenity", "atm"},
         // 2
         {"amenity", "bank"}},
        {1, 1}, drule::symbol);
  }

  {
    CheckPriority(
        {
            // 1
            {"amenity", "bench"},
            {"amenity", "shelter"},
            // 2
            {"highway", "bus_stop"},
            {"amenity", "bus_station"},
            {"railway", "station"},
            {"railway", "halt"},
            {"railway", "tram_stop"},
        },
        {2, 5}, drule::symbol);
  }

  /// @todo Check that all of sport=* icons priority is bigger than all of pitch, sports_center, recreation_ground.

  {
    CheckPriority(
        {// 1
         {"leisure", "pitch"},
         // 2
         {"sport", "yoga"}},
        {1, 1}, drule::symbol);
  }

  {
    CheckPriority(
        {// 1
         {"leisure", "fitness_centre"},
         // 2
         {"sport", "pilates"},
         {"sport", "yoga"}},
        {1, 2}, drule::symbol);
  }

  {
    CheckPriority(
        {// 1
         {"leisure", "sports_centre"},
         // 2
         {"sport", "shooting"}},
        {1, 1}, drule::symbol);
  }

  {
    CheckPriority(
        {// 1
         {"landuse", "recreation_ground"},
         // 2
         {"sport", "multi"}},
        {1, 1}, drule::symbol);
  }
}

// A specific water type with a caption should be the main one for captions and the place page,
// no matter the types order.
UNIT_TEST(Classificator_IntermittentWaterCaptionPriority)
{
  CheckPriority(
      {
          // 1
          {"natural", "water", "intermittent"},
          // 2
          {"natural", "water", "basin"},
          {"natural", "water", "ditch"},
          {"natural", "water", "drain"},
          {"natural", "water", "lake"},
          {"natural", "water", "lock"},
          {"natural", "water", "moat"},
          {"natural", "water", "pond"},
          {"natural", "water", "reservoir"},
          {"natural", "water", "river"},
          {"natural", "water", "wastewater"},
      },
      {1, 10}, drule::caption);
}

// An intermittent waterway is drawn and labelled like its base waterway, only dashed, with a longer gap if the base
// is already dashed.
UNIT_TEST(Classificator_IntermittentWaterwayRules)
{
  styles::RunForEveryMapStyle([](MapStyle style)
  {
    auto const & rules = drule::GetCurrentRules();
    auto const getKeys = [](base::StringIL const & path, int level)
    {
      drule::KeysT keys;
      GetDrawRule({classif().GetTypeByPath(path)}, level, GeomType::Line, keys);
      return keys;
    };

    for (int level = scales::GetUpperWorldScale() + 1; level <= scales::GetUpperStyleScale(); ++level)
    {
      for (char const * base : {"canal", "ditch", "drain", "fish_pass", "river"})
      {
        auto const baseKeys = getKeys({"waterway", base}, level);
        auto const keys = getKeys({"waterway", base, "intermittent"}, level);
        TEST_EQUAL(keys.size(), baseKeys.size(), (style, base, level));
        for (size_t i = 0; i < keys.size(); ++i)
        {
          TEST_EQUAL(keys[i].m_type, baseKeys[i].m_type, (style, base, level));
          TEST_EQUAL(keys[i].m_priority, baseKeys[i].m_priority, (style, base, level));
          if (keys[i].m_type == drule::pathtext)
            TEST(*rules.Find(keys[i])->GetPathtext() == *rules.Find(baseKeys[i])->GetPathtext(), (style, base, level));
          if (keys[i].m_type != drule::line)
            continue;
          auto line = *rules.Find(keys[i])->GetLine();
          auto const & baseLine = *rules.Find(baseKeys[i])->GetLine();
          TEST(line.dashdot, (style, base, level));
          TEST_EQUAL(line.dashdot->dd.size(), 2, (style, base, level));
          if (baseLine.dashdot)
            TEST_EQUAL(baseLine.dashdot->dd.size(), 2, (style, base, level));
          TEST(!baseLine.dashdot || line.dashdot->dd[1] > baseLine.dashdot->dd[1], (style, base, level));
          line.dashdot = baseLine.dashdot;
          TEST(line == baseLine, (style, base, level));
        }
      }
    }
  });
}

namespace
{
class MikshatRoadObject : public osm::MapObject
{
public:
  explicit MikshatRoadObject(std::string_view highway, std::string_view surface = {}, bool tunnel = false,
                             std::string_view service = {})
  {
    m_geomType = GeomType::Line;
    m_points = {{0, 0}, {0.01, 0.01}};
    if (!service.empty())
      m_types.Add(classif().GetTypeByPath({"highway", "service", service}));
    else
      m_types.Add(tunnel ? classif().GetTypeByPath({"highway", highway, "tunnel"})
                         : classif().GetTypeByPath({"highway", highway}));
    if (!surface.empty())
      m_types.Add(classif().GetTypeByPath({"psurface", surface}));
    m_name.Add("en", "Outdoor road");
  }
};

class MikshatLocalityObject : public osm::MapObject
{
public:
  explicit MikshatLocalityObject(std::string_view name)
  {
    m_geomType = GeomType::Point;
    m_points = {{0, 0}};
    m_types.Add(classif().GetTypeByPath({"place", "locality"}));
    m_name.Add("default", name);
    m_name.Add("ar", name);
  }
};

drule::BaseRule const * GetMikshatRule(base::StringIL const & path, int level, GeomType geometry, drule::TypeT kind)
{
  drule::KeysT keys;
  GetDrawRule({classif().GetTypeByPath(path)}, level, geometry, keys);
  for (auto const & key : keys)
    if (key.m_type == kind)
      return drule::GetCurrentRules().Find(key);
  return nullptr;
}
}  // namespace

// Read the shipped binary drawing rules, including both palettes and all
// browsing/navigation families. MapCSS text alone is not the app's style.
UNIT_TEST(Classificator_MikshatOutdoorLabels)
{
  styles::RunForEveryMapStyle([](MapStyle style)
  {
    uint32_t const settlementColor = MapStyleIsDark(style) ? 0xFF8D86 : 0xBD162C;
    uint32_t const wadiColor = MapStyleIsDark(style) ? 0x68BFFF : 0x0000FF;
    for (auto const & path : vector<base::StringIL>{{"place", "village"}, {"place", "hamlet"}})
    {
      for (int const zoom : {9, 10, 13, 17})
      {
        auto const * rule = GetMikshatRule(path, zoom, GeomType::Point, drule::caption);
        TEST(rule && rule->GetCaption() && rule->GetCaption()->primary, (style, path, zoom));
        auto const & caption = *rule->GetCaption()->primary;
        TEST_EQUAL(caption.color & 0xFFFFFF, settlementColor, (style, path, zoom));
        TEST_GREATER_OR_EQUAL(caption.height, zoom >= 13 ? 14 : 12, (style, path, zoom));
      }
    }
    auto const * city = GetMikshatRule({"place", "city"}, 11, GeomType::Point, drule::caption);
    TEST(city && city->GetCaption() && city->GetCaption()->primary, (style));
    TEST_GREATER_OR_EQUAL(city->GetCaption()->primary->height, 16, (style));

    uint32_t const faydaColor = MapStyleIsDark(style) ? 0x7AD49A : 0x207440;
    for (auto const & path : vector<base::StringIL>{{"landuse", "meadow"}, {"natural", "grassland"}})
    {
      auto const * rule = GetMikshatRule(path, 10, GeomType::Area, drule::caption);
      TEST(rule && rule->GetCaption() && rule->GetCaption()->primary, (style, path));
      TEST_EQUAL(rule->GetCaption()->primary->color & 0xFFFFFF, faydaColor, (style, path));
    }

    for (auto const & path : vector<base::StringIL>{{"waterway", "river"},
                                                    {"waterway", "river", "intermittent"},
                                                    {"waterway", "stream"},
                                                    {"waterway", "stream", "intermittent"}})
    {
      for (int const zoom : {9, 10, 13, 17})
      {
        auto const * rule = GetMikshatRule(path, zoom, GeomType::Line, drule::pathtext);
        TEST(rule && rule->GetPathtext() && rule->GetPathtext()->primary, (style, path, zoom));
        TEST_EQUAL(rule->GetPathtext()->primary->color & 0xFFFFFF, wadiColor, (style, path, zoom));
      }
    }
  });
}

UNIT_TEST(Classificator_MikshatResourcesAndTracks)
{
  styles::RunForEveryMapStyle([](MapStyle style)
  {
    for (auto const & path : vector<base::StringIL>{{"amenity", "fuel"},
                                                    {"natural", "spring"},
                                                    {"natural", "hot_spring"},
                                                    {"man_made", "water_well"},
                                                    {"man_made", "water_tap"},
                                                    {"amenity", "water_point"},
                                                    {"amenity", "drinking_water"}})
    {
      auto const * rule = GetMikshatRule(path, 10, GeomType::Point, drule::symbol);
      TEST(rule && rule->GetSymbol(), (style, path));
      TEST_EQUAL(rule->GetSymbol()->name, path.begin()[1] == "fuel" ? "fuel-s" : "drinking-water-s", (style, path));
      TEST_GREATER_OR_EQUAL(rule->GetSymbol()->min_distance, 48, (style, path));
    }

    for (auto const & path : vector<base::StringIL>{{"natural", "spring", "drinking_water_no"},
                                                    {"man_made", "water_well", "drinking_water_no"},
                                                    {"amenity", "water_point", "drinking_water_no"}})
    {
      for (int const zoom : {10, 17})
      {
        auto const * rule = GetMikshatRule(path, zoom, GeomType::Point, drule::symbol);
        TEST(rule && rule->GetSymbol(), (style, path, zoom));
        TEST_EQUAL(rule->GetSymbol()->name, zoom == 10 ? "drinking-water-no-s" : "drinking-water-no-m",
                   (style, path, zoom));
      }
    }

    auto const * trackName = GetMikshatRule({"highway", "track"}, 9, GeomType::Line, drule::pathtext);
    TEST(trackName && trackName->GetPathtext() && trackName->GetPathtext()->primary, (style));

    uint32_t const trackColor = MapStyleIsDark(style) ? 0xC79A66 : 0x635730;
    for (int const zoom : {6, 9, 10, 14, 17, 19})
    {
      auto feature = FeatureType::CreateFromMapObject(MikshatRoadObject("track"));
      drule::KeysT keys;
      GetDrawRule({classif().GetTypeByPath({"highway", "track"})}, zoom, GeomType::Line, keys);
      FilterRulesByRuntimeSelector(*feature, zoom, drule::GetCurrentRules(), keys);
      bool hasDirtTrack = false;
      for (auto const & key : keys)
      {
        auto const * line = drule::GetCurrentRules().Find(key)->GetLine();
        if (line && (line->color & 0xFFFFFF) == trackColor)
        {
          TEST(!line->dashdot, (style, zoom));
          hasDirtTrack = true;
        }
      }
      TEST(hasDirtTrack, (style, zoom));
    }
    for (int const zoom : {6, 9, 14, 17})
    {
      auto feature = FeatureType::CreateFromMapObject(MikshatRoadObject("track", "paved_good"));
      drule::KeysT keys;
      GetDrawRule({classif().GetTypeByPath({"highway", "track"})}, zoom, GeomType::Line, keys);
      FilterRulesByRuntimeSelector(*feature, zoom, drule::GetCurrentRules(), keys);
      bool hasPavedTrack = false;
      for (auto const & key : keys)
        if (auto const * line = drule::GetCurrentRules().Find(key)->GetLine())
        {
          TEST(line->dashdot, ("Explicitly paved tracks retain their existing stroke", style, zoom));
          hasPavedTrack = true;
        }
      TEST_EQUAL(hasPavedTrack, zoom >= 9, (style, zoom));
    }
    for (auto const highway :
         {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
          "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "road", "service", "track"})
      for (int zoom = 6; zoom <= 19; ++zoom)
      {
        auto feature = FeatureType::CreateFromMapObject(MikshatRoadObject(highway, "unpaved_good"));
        drule::KeysT keys;
        GetDrawRule({classif().GetTypeByPath({"highway", highway})}, zoom, GeomType::Line, keys);
        FilterRulesByRuntimeSelector(*feature, zoom, drule::GetCurrentRules(), keys);
        bool visible = false;
        bool named = false;
        for (auto const & key : keys)
        {
          auto const * rule = drule::GetCurrentRules().Find(key);
          if (auto const * line = rule->GetLine())
          {
            TEST(!line->dashdot, (style, highway, zoom));
            visible = visible || (line->width > 0 && (line->color & 0xFFFFFF) == trackColor);
          }
          if (auto const * text = rule->GetPathtext())
            named = named || (text->primary && text->primary->height >= 10);
        }
        TEST(visible, ("Dirt roads need continuous overview/detail eligibility", style, highway, zoom));
        TEST(named, ("Dirt-road names need continuous overview/detail eligibility", style, highway, zoom));
      }
    for (auto const service : {"driveway", "parking_aisle"})
      for (int const zoom : {13, 14, 15})
      {
        auto feature = FeatureType::CreateFromMapObject(MikshatRoadObject("service", "unpaved_good", false, service));
        drule::KeysT keys;
        GetDrawRule({classif().GetTypeByPath({"highway", "service", service})}, zoom, GeomType::Line, keys);
        FilterRulesByRuntimeSelector(*feature, zoom, drule::GetCurrentRules(), keys);
        bool visible = false;
        bool named = false;
        for (auto const & key : keys)
        {
          auto const * rule = drule::GetCurrentRules().Find(key);
          if (auto const * line = rule->GetLine())
          {
            TEST(!line->dashdot, (style, service, zoom));
            visible = visible || (line->width > 0 && (line->color & 0xFFFFFF) == trackColor);
          }
          if (auto const * text = rule->GetPathtext())
            named = named || (text->primary && text->primary->height >= 10);
        }
        TEST(visible && named, ("Unpaved service subtypes must not disappear at closer scales", style, service, zoom));
      }
    for (auto const highway :
         {"primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service", "track"})
      for (int const zoom : {14, 17, 19})
      {
        auto feature = FeatureType::CreateFromMapObject(MikshatRoadObject(highway, "unpaved_good", true));
        drule::KeysT keys;
        GetDrawRule({classif().GetTypeByPath({"highway", highway, "tunnel"})}, zoom, GeomType::Line, keys);
        FilterRulesByRuntimeSelector(*feature, zoom, drule::GetCurrentRules(), keys);
        bool visible = false;
        for (auto const & key : keys)
          if (auto const * line = drule::GetCurrentRules().Find(key)->GetLine())
          {
            TEST(!line->dashdot, ("Dirt-road casings must also be solid", style, highway, zoom));
            visible = visible || (line->width > 0 && (line->color & 0xFFFFFF) == trackColor);
          }
        TEST(visible, (style, highway, zoom));
      }
  });
}

UNIT_TEST(Classificator_MikshatLandAndProtectedPalette)
{
  styles::RunForEveryMapStyle([](MapStyle style)
  {
    // The removed country-coverage overlay must not tint any land or water.
    TEST(!GetMikshatRule({"organicapp", "mwm_border"}, 5, GeomType::Area, drule::area), (style));
    if (!MapStyleIsDark(style))
    {
      auto const * sand = GetMikshatRule({"natural", "desert"}, 15, GeomType::Area, drule::area);
      TEST(sand && sand->GetArea(), (style));
      TEST_EQUAL(sand->GetArea()->color & 0xFFFFFF, 0xEBA426, ("Actual shipped 4.6.16 sand", style));
    }
    for (auto const & path : vector<base::StringIL>{{"natural", "desert"}, {"natural", "beach", "sand"}})
      for (int const zoom : {6, 9, 14, 19})
        for (auto const geometry : {GeomType::Point, GeomType::Area})
        {
          auto const * name = GetMikshatRule(path, zoom, geometry, drule::caption);
          TEST(name && name->GetCaption() && name->GetCaption()->primary, (style, path, zoom, geometry));
          auto const & text = *name->GetCaption()->primary;
          TEST_EQUAL(text.color & 0xFFFFFF, 0, (style, path, zoom));
          TEST_EQUAL(text.stroke_color & 0xFFFFFF, 0xFFFFFF, (style, path, zoom));
          TEST_GREATER_OR_EQUAL(text.height, 14, (style, path, zoom));
        }
    for (auto const name : {"خب أبو خصام", "طعس مشرف", "الأمغر", "خب حشمة", "موقع بري آخر", "فيضة الخويش"})
    {
      auto feature = FeatureType::CreateFromMapObject(MikshatLocalityObject(name));
      bool const fayda = std::string_view(name) == "فيضة الخويش";
      uint32_t const expectedColor = fayda ? (MapStyleIsDark(style) ? 0x7AD49A : 0x207440) : 0;
      for (int const zoom : {6, 9, 14, 19})
      {
        drule::KeysT keys;
        GetDrawRule({classif().GetTypeByPath({"place", "locality"})}, zoom, GeomType::Point, keys);
        FilterRulesByRuntimeSelector(*feature, zoom, drule::GetCurrentRules(), keys);
        bool found = false;
        for (auto const & key : keys)
          if (auto const * caption = drule::GetCurrentRules().Find(key)->GetCaption())
          {
            TEST(caption->primary, (style, name, zoom));
            TEST_EQUAL(caption->primary->color & 0xFFFFFF, expectedColor, (style, name, zoom));
            TEST_GREATER_OR_EQUAL(caption->primary->height, fayda ? 12 : 14, (style, name, zoom));
            found = true;
          }
        TEST(found, (style, name, zoom));
      }
    }
    uint32_t const fillColor = MapStyleIsDark(style) ? 0x6E528A : 0xCFB8E8;
    uint32_t const borderColor = MapStyleIsDark(style) ? 0xBE97DF : 0x8557AC;
    for (auto const & path : vector<base::StringIL>{{"boundary", "national_park"},
                                                    {"boundary", "protected_area"},
                                                    {"boundary", "protected_area", "1"},
                                                    {"boundary", "protected_area", "2"},
                                                    {"boundary", "protected_area", "3"},
                                                    {"boundary", "protected_area", "4"},
                                                    {"boundary", "protected_area", "5"},
                                                    {"boundary", "protected_area", "6"},
                                                    {"leisure", "nature_reserve"}})
    {
      float previousWidth = 0;
      for (int const zoom : {6, 9, 10, 13, 16, 19})
      {
        auto const * fill = GetMikshatRule(path, zoom, GeomType::Area, drule::area);
        TEST(fill && fill->GetArea(), (style, path, zoom));
        TEST_EQUAL(fill->GetArea()->color & 0xFFFFFF, fillColor, (style, path, zoom));
        for (auto const geometry : {GeomType::Point, GeomType::Area})
        {
          auto const * name = GetMikshatRule(path, zoom, geometry, drule::caption);
          TEST(name && name->GetCaption() && name->GetCaption()->primary, (style, path, zoom, geometry));
          TEST_EQUAL(name->GetCaption()->primary->color & 0xFFFFFF, borderColor, (style, path, zoom));
          TEST_GREATER_OR_EQUAL(name->GetCaption()->primary->height, 12, (style, path, zoom));
        }
        auto const * border = GetMikshatRule(path, zoom, GeomType::Line, drule::line);
        TEST(border && border->GetLine(), (style, path, zoom));
        TEST_EQUAL(border->GetLine()->color & 0xFFFFFF, borderColor, (style, path, zoom));
        TEST(!border->GetLine()->dashdot, (style, path, zoom));
        TEST_GREATER_OR_EQUAL(border->GetLine()->width, previousWidth, (style, path, zoom));
        previousWidth = border->GetLine()->width;
      }
      TEST_GREATER(previousWidth, 1, ("Protected boundaries must become thicker at closer scales", style, path));
    }
  });
}

namespace
{
struct RangeEntry
{
  uint32_t m_type;
  std::pair<int, int> m_range;

  // From C++ 20.
  // auto operator<=>(RangeEntry const &) const = default;
  bool operator!=(RangeEntry const & rhs) const { return m_type != rhs.m_type || m_range != rhs.m_range; }

  friend std::string DebugPrint(RangeEntry const & e)
  {
    std::ostringstream ss;
    ss << classif().GetReadableObjectName(e.m_type) << "; (" << e.m_range.first << "," << e.m_range.second << ")";
    return ss.str();
  }
};
}  // namespace

UNIT_TEST(Classificator_HighwayZoom_AcrossStyles)
{
  std::array<std::vector<RangeEntry>, MapStyleCount> scales;

  styles::RunForEveryMapStyle([&scales](MapStyle style)
  {
    auto const & cl = classif();
    uint32_t const type = cl.GetTypeByPath({"highway"});
    ClassifObject const * pObj = cl.GetObject(type);

    pObj->ForEachObjectInTree([&scales, style](ClassifObject const *, uint32_t type)
    {
      TypesHolder holder(GeomType::Line);
      holder.Add(type);
      scales[style].push_back({type, GetDrawableScaleRangeForRules(holder, RULE_LINE)});
    }, type);
  });

  for (size_t iStyle = 1; iStyle < MapStyleCount; ++iStyle)
  {
    if (iStyle == MapStyleMerged)
      continue;

    // Don't put TEST, only diagnostic logs. In general, Clear and Vehical visibility styles are different
    // for highways like: footway, path, steps, cycleway, bridleway, track, service.
    TEST_EQUAL(scales[0].size(), scales[iStyle].size(), (iStyle));
    for (size_t j = 0; j < scales[0].size(); ++j)
      if (scales[0][j] != scales[iStyle][j])
        LOG(LWARNING, (scales[0][j], scales[iStyle][j]));
  }
}
}  // namespace classificator_tests
