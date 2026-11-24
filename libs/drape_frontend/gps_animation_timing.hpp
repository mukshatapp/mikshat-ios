#pragma once

#include <algorithm>
#include <cmath>

namespace df
{
inline constexpr double kMaxGpsAnimationTimeSec = 1.2;

// Visual interpolation only: never extrapolate positions or change recorded GPS data.
class GpsAnimationTiming
{
public:
  double Update(double monotonicSeconds, bool moving)
  {
    double result = 0.20;
    if (m_last >= 0.0)
    {
      double const interval = monotonicSeconds - m_last;
      if (std::isfinite(interval) && interval > 0.0 && interval <= 3.0)
      {
        m_interval = 0.5 * m_interval + 0.5 * interval;
        result = std::clamp(1.05 * m_interval, 0.12, kMaxGpsAnimationTimeSec);
      }
      else
        m_interval = 0.8;
    }
    m_last = monotonicSeconds;
    return moving ? result : 0.12;
  }
private:
  double m_last = -1.0;
  double m_interval = 0.8;
};
}  // namespace df
