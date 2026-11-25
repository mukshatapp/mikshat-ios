#pragma once

#include <cstdint>
#include <string_view>

namespace platform::map_compatibility
{
// The map-server protocol version follows the engine, independently of Mikshat's app version.
// Update these pins together with the engine and bundled catalogue/World maps.
inline constexpr std::string_view kEngineRelease = "2026.11.11-39";
inline constexpr std::string_view kEngineCommit = "5c0c5ec0a706b9bea17b4d5b0b40e7b60f916a13";
inline constexpr int64_t kDataVersion = 261110;
}  // namespace platform::map_compatibility
