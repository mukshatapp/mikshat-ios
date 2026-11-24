#include "drape_frontend/direct_guide_presentation.hpp"
#include <cassert>
#include <iostream>
int main()
{
  for (double scale : {1.0, 1.3, 1.5, 2.0})
    for (double height : {600.0, 720.0, 1280.0, 1600.0})
    {
      auto const original = height - 104.0 * scale;
      auto const lifted = df::DirectGuideAnchorY(original, 0.0, height, scale, true, true);
      assert(lifted < original && lifted >= 24.0 * scale);
      assert(df::DirectGuideAnchorY(original, 0, height, scale, false, true) == original);
      assert(df::DirectGuideAnchorY(original, 0, height, scale, true, false) == original);
    }
  assert(df::DirectGuideAnchorY(100, 100, 100, 1, true, true) == 100);
  std::cout << "PASS direct portrait anchor, safe bounds, landscape and other modes retained\n";
}
