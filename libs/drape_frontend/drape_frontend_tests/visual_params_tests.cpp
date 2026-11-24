#include "testing/testing.hpp"

#include "drape_frontend/gui/ruler_helper.hpp"
#include "drape_frontend/render_state_extension.hpp"
#include "drape_frontend/visual_params.hpp"

#include "indexer/mikshat_map_visibility.hpp"

#include "platform/measurement_utils.hpp"
#include "platform/settings.hpp"

#include "geometry/mercator.hpp"

#include "base/scope_guard.hpp"

#include <algorithm>
#include <array>
#include <map>
#include <set>
#include <string_view>
#include <tuple>

namespace visual_params_tests
{
UNIT_TEST(DrawTileScale_DependsOnVisualScale)
{
  uint32_t constexpr kTileSize = 1024;
  int constexpr kBaseScale = 10;
  double constexpr kRectSize = mercator::Bounds::kRangeX / (1 << kBaseScale);
  m2::RectD const rect(0.0, 0.0, kRectSize, kRectSize);

  TEST_EQUAL(df::GetDrawTileScale(rect, kTileSize, 3.0), kBaseScale, ());
  TEST_EQUAL(df::GetDrawTileScale(rect, kTileSize, 2.0), kBaseScale + 1, ());
}

UNIT_TEST(Mikshat_TwentyKilometreRulerUsesOverviewZoom)
{
  auto const previousUnits = measurement_utils::GetMeasurementUnits();
  settings::Set(settings::kMeasurementUnits, measurement_utils::Units::Metric);
  SCOPE_GUARD(RestoreUnits, [previousUnits] { settings::Set(settings::kMeasurementUnits, previousUnits); });
  SCOPE_GUARD(RestoreVisualParams, [] { df::VisualParams::Init(1.0, 1024); });

  std::set<int> observedZooms;
  // Real iPhone/iPad logical viewports, with their native visual density.
  for (auto const & device : {std::array<int, 3>{414, 896, 3}, {393, 852, 3}, {1024, 1366, 2}})
  {
    int const width = device[0] * device[2];
    int const height = device[1] * device[2];
    df::VisualParams::Init(device[2], df::CalculateTileSize(width, height));
    for (double const latitude : {16.0, 25.0, 32.0})
    {
      auto const center = mercator::FromLatLon(latitude, 45.0);
      for (double const measuredMetres : {15100.0, 17500.0, 19900.0})
      {
        auto const east = mercator::GetSmPoint(center, measuredMetres, 0.0);
        ScreenBase screen;
        screen.OnSize(0, 0, width, height);
        screen.SetFromParams(center, 0.0, (east.x - center.x) / (60.0 * device[2]));
        gui::RulerHelper ruler;
        ruler.Update(screen);
        TEST_EQUAL(ruler.GetRulerText(), "20 km", (device, latitude, measuredMetres));
        int const zoom = df::GetDrawTileScale(screen);
        TEST(zoom == 9 || zoom == 10, (device, latitude, measuredMetres, zoom));
        observedZooms.insert(zoom);
      }
    }
  }
  TEST(!observedZooms.empty(), ());
  TEST(std::all_of(observedZooms.begin(), observedZooms.end(), [](int zoom) { return zoom >= 6 && zoom <= 14; }), ());
}

UNIT_TEST(Mikshat_ProtectedAreaFillUsesActualTwoKilometreRuler)
{
  auto const previousUnits = measurement_utils::GetMeasurementUnits();
  SCOPE_GUARD(RestoreUnits, [previousUnits] { settings::Set(settings::kMeasurementUnits, previousUnits); });
  SCOPE_GUARD(RestoreVisualParams, [] { df::VisualParams::Init(1.0, 1024); });
  std::set<int> observedZooms;
  for (auto const & device : {std::array<int, 3>{414, 896, 3}, {393, 852, 3}, {1024, 1366, 2}})
  {
    int const width = device[0] * device[2];
    int const height = device[1] * device[2];
    df::VisualParams::Init(device[2], df::CalculateTileSize(width, height));
    for (double const latitude : {16.0, 25.0, 32.0})
      for (auto const & [metres, rulerMetres, text] :
           {std::tuple<double, double, std::string_view>{1010.0, 2000.0, "2 km"},
            {1500.0, 2000.0, "2 km"},
            {1990.0, 2000.0, "2 km"},
            {2010.0, 5000.0, "5 km"},
            {4990.0, 5000.0, "5 km"},
            {510.0, 1000.0, "1 km"},
            {110.0, 200.0, "200 m"}})
      {
        auto const center = mercator::FromLatLon(latitude, 45.0);
        auto const east = mercator::GetSmPoint(center, metres, 0.0);
        ScreenBase screen;
        screen.OnSize(0, 0, width, height);
        screen.SetFromParams(center, 0.0, (east.x - center.x) / (60.0 * device[2]));
        settings::Set(settings::kMeasurementUnits, measurement_utils::Units::Metric);
        gui::RulerHelper ruler;
        ruler.Update(screen);
        TEST_EQUAL(ruler.GetRulerText(), text, (device, latitude, metres));
        TEST_EQUAL(gui::RulerHelper::GetMetricRulerDistance(screen), rulerMetres, (device, latitude, metres));
        TEST_EQUAL(df::IsProtectedAreaFillVisible(screen), text == "5 km", (device, latitude, metres));
        if (rulerMetres == 2000.0)
          observedZooms.insert(df::GetDrawTileScale(screen));

        settings::Set(settings::kMeasurementUnits, measurement_utils::Units::Imperial);
        TEST_EQUAL(gui::RulerHelper::GetMetricRulerDistance(screen), rulerMetres, (device, latitude, metres));
        TEST_EQUAL(df::IsProtectedAreaFillVisible(screen), text == "5 km", (device, latitude, metres));
      }
  }
  // A fixed zoom cutoff cannot represent every screen on which the actual ruler says 2 km.
  TEST_GREATER(observedZooms.size(), 1, (observedZooms));
}
UNIT_TEST(Mikshat_OutdoorCategoryVisibilityUsesActualRuler)
{
  auto const previousUnits = measurement_utils::GetMeasurementUnits();
  SCOPE_GUARD(RestoreUnits, [previousUnits] { settings::Set(settings::kMeasurementUnits, previousUnits); });
  SCOPE_GUARD(RestoreVisualParams, [] { df::VisualParams::Init(1.0, 1024); });
  std::map<int, std::set<uint8_t>> policiesByDrawZoom;
  for (auto const & device : {std::array<int, 3>{414, 896, 3}, {393, 852, 3}, {1024, 1366, 2}})
    for (bool const landscape : {false, true})
    {
      int const width = device[landscape ? 1 : 0] * device[2];
      int const height = device[landscape ? 0 : 1] * device[2];
      df::VisualParams::Init(device[2], df::CalculateTileSize(width, height));
      for (double const latitude : {16.0, 25.0, 32.0})
        for (auto const & [metres, rulerMetres, text, visibility] :
             {std::tuple<double, double, std::string_view, uint8_t>{50100.0, 100000.0, "100 km", 0},
              {49900.0, 50000.0, "50 km", feature::kMikshatProtectedVisibility},
              {20100.0, 50000.0, "50 km", feature::kMikshatProtectedVisibility},
              {19900.0, 20000.0, "20 km", feature::kMikshatProtectedVisibility | feature::kMikshatOutdoorVisibility},
              {15100.0, 20000.0, "20 km", feature::kMikshatProtectedVisibility | feature::kMikshatOutdoorVisibility},
              {14900.0, 15000.0, "15 km", feature::kMikshatAllVisibility},
              {10100.0, 15000.0, "15 km", feature::kMikshatAllVisibility},
              {9900.0, 10000.0, "10 km", feature::kMikshatAllVisibility}})
        {
          auto const center = mercator::FromLatLon(latitude, 45.0);
          auto const east = mercator::GetSmPoint(center, metres, 0.0);
          ScreenBase screen;
          screen.OnSize(0, 0, width, height);
          screen.SetFromParams(center, 0.0, (east.x - center.x) / (60.0 * device[2]));
          settings::Set(settings::kMeasurementUnits, measurement_utils::Units::Metric);
          gui::RulerHelper ruler;
          ruler.Update(screen);
          TEST_EQUAL(ruler.GetRulerText(), text, (device, landscape, latitude, metres));
          TEST_EQUAL(gui::RulerHelper::GetMetricRulerDistance(screen), rulerMetres, ());
          auto const policy = feature::GetMikshatOutdoorVisibility(gui::RulerHelper::GetMetricRulerDistance(screen));
          TEST_EQUAL(policy, visibility, (device, landscape, latitude, metres));
          policiesByDrawZoom[df::GetDrawTileScale(screen)].insert(policy);

          settings::Set(settings::kMeasurementUnits, measurement_utils::Units::Imperial);
          TEST_EQUAL(feature::GetMikshatOutdoorVisibility(gui::RulerHelper::GetMetricRulerDistance(screen)), visibility,
                     ("Unit preferences must not change category eligibility"));
        }
    }
  TEST(std::any_of(policiesByDrawZoom.begin(), policiesByDrawZoom.end(),
                   [](auto const & entry) { return entry.second.size() > 1; }),
       ("One fixed draw zoom cannot represent the requested ruler thresholds"));
}
}  // namespace visual_params_tests
