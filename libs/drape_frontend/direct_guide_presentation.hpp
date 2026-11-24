#pragma once

#include <algorithm>
#include <atomic>

namespace df
{
// GUI routing state is read by the rendering thread; coordinates are never offset.
inline std::atomic<bool> g_mukshatDirectGuide{false};

inline double DirectGuideAnchorY(double original, double top, double bottom, double visualScale,
                                 bool portrait, bool direct)
{
  if (!portrait || !direct || bottom <= top)
    return original;
  double const lift = std::clamp((bottom - top) * 0.06, 24.0 * visualScale, 48.0 * visualScale);
  return std::max(top + 24.0 * visualScale, original - lift);
}
}  // namespace df
