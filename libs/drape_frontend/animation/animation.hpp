#pragma once

#include "drape_frontend/animation_constants.hpp"
#include "drape_frontend/gps_animation_timing.hpp"

#include "base/assert.hpp"

#include <algorithm>

namespace df
{
class Animation
{
public:
  double GetRemainingTime(AnimationClock::time_point now) const { return std::max(0.0, m_duration - Elapsed(now)); }
  bool IsFinished() const { return m_timeFraction == 1.0; }
  void Advance(AnimationClock::time_point now) { m_timeFraction = std::clamp(Elapsed(now) / m_duration, 0.0, 1.0); }

protected:
  Animation(AnimationClock::time_point requestedAt, double duration, bool continuousGps = false)
    : m_requestedAt(requestedAt), m_duration(duration), m_continuousGps(continuousGps)
  {
    ASSERT(duration > 0.0 && duration <= (continuousGps ? kMaxGpsAnimationTimeSec : kMaxAnimationTimeSec), (duration));
  }

  double GetTimeFraction() const { return m_timeFraction; }
  double GetProgress() const
  {
    if (m_continuousGps)
      return m_timeFraction;
    double const remaining = 1.0 - m_timeFraction;
    return 1.0 - remaining * remaining * remaining;
  }

private:
  double Elapsed(AnimationClock::time_point now) const
  {
    return std::chrono::duration<double>(now - m_requestedAt).count();
  }

  AnimationClock::time_point const m_requestedAt;
  double const m_duration;
  double m_timeFraction = 0.0;
  bool const m_continuousGps;
};
}  // namespace df
