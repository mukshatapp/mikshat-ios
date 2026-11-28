#include "drape_frontend/mukshat_detail_visibility.hpp"

#include <array>
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

int main()
{
  using namespace df::mukshat;
  constexpr auto infinity = std::numeric_limits<double>::infinity();
  std::array<double, 9> const distance{0.0, 1.0, std::nextafter(2000.0, -infinity), 2000.0,
                                      std::nextafter(2000.0, infinity), std::nextafter(5000.0, -infinity),
                                      5000.0, std::nextafter(5000.0, infinity), 1000000.0};
  std::array<DetailVisibilityMask, 9> const expected{3, 3, 3, 1, 1, 1, 0, 0, 0};
  size_t checks = 0;
  for (size_t i = 0; i < distance.size(); ++i)
  {
    auto const mask = GetDetailVisibilityMask(distance[i]);
    assert(mask == expected[i]);
    assert(CanShow(MapDetailKind::DirtRoad, mask) == (distance[i] < 5000.0));
    assert(CanShow(MapDetailKind::IntermittentStream, mask) == (distance[i] < 2000.0));
    assert(CanShow(MapDetailKind::PowerLine, mask) == (distance[i] < 2000.0));
    assert(CanShow(MapDetailKind::Other, mask));
    assert(CanShow(MapDetailKind::Scrub, mask));
    checks += 6;
  }
  // A copied per-read value remains stable after subsequent viewport bucket changes.
  auto live = GetDetailVisibilityMask(1900.0);
  auto const oldRead = live;
  live = GetDetailVisibilityMask(6000.0);
  assert(oldRead == kAllDetailVisibility);
  assert(live == 0);
  assert(CanShow(MapDetailKind::PowerLine, oldRead));
  assert(!CanShow(MapDetailKind::PowerLine, live));
  checks += 4;
  static_assert(GetDetailVisibilityMask(2000.0) == kShowDirtRoads);
  static_assert(GetDetailVisibilityMask(5000.0) == 0);
  std::cout << "PASS: " << checks << " dynamic detail visibility checks\n";
}
