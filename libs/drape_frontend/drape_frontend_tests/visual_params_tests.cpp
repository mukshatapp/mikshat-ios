#include "testing/testing.hpp"

#include "drape_frontend/gui/ruler_helper.hpp"
#include "drape_frontend/visual_params.hpp"

#include "platform/measurement_utils.hpp"
#include "platform/settings.hpp"

#include "geometry/mercator.hpp"

#include "base/scope_guard.hpp"

#include <array>
#include <set>

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
      for (double const measuredMetres : {10100.0, 15000.0, 19900.0})
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
  TEST_EQUAL(observedZooms, (std::set<int>{9, 10}), ());
}
}  // namespace visual_params_tests
