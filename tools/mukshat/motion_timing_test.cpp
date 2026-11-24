#include "drape_frontend/gps_animation_timing.hpp"
#include <cassert>
#include <iostream>
int main()
{
  df::GpsAnimationTiming timing;
  assert(timing.Update(1.0, true) == 0.20);
  for (int i = 2; i < 100; ++i)
  {
    double const duration = timing.Update(i, true);
    assert(duration >= 0.12 && duration <= 0.80);
  }
  assert(timing.Update(100.0, false) == 0.12);
  assert(timing.Update(110.0, true) == 0.20);
  assert(timing.Update(109.0, true) == 0.20);
  for (int i = 0; i < 100; ++i)
  {
    double const duration = timing.Update(111.0 + i * 0.1, true);
    assert(duration >= 0.12 && duration <= 0.80);
  }
  std::cout << "PASS monotonic cadence, bounded lag, stop, sparse fixes and clock reset\n";
}
