#pragma once

#include <string_view>

namespace df
{
// Reserve fill keeps its own overlay slot so land-cover on the same feature survives.
inline constexpr std::string_view kProtectedAreaFillOverlay = "mukshat-protected-area-fill";
}  // namespace df
