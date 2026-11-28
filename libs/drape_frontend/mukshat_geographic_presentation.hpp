#pragma once

#include <array>
#include <string_view>

namespace df::mukshat
{
inline constexpr float kPreviousCaptionSizeFactor = 1.2f;
inline constexpr float kCaptionIncrementFactor = 1.15f;
inline constexpr float kCaptionSizeFactor = kPreviousCaptionSizeFactor * kCaptionIncrementFactor;
inline constexpr double kReserveBorderDepthOffset = 0.01;

enum class GeographicNameKind
{
  Other,
  Depression,
  Watercourse
};

inline bool HasGeographicPrefix(std::string_view name, std::string_view prefix)
{
  if (!name.starts_with(prefix))
    return false;
  auto const remainder = name.substr(prefix.size());
  return remainder.empty() || remainder.starts_with(' ') || remainder.starts_with('\t') || remainder.starts_with(" ");
}

// Supplemental maps encode these landforms as generic localities. Match complete
// Arabic feature-name words, never substrings or settled-place/POI types.
inline GeographicNameKind ClassifyGeographicName(std::string_view name)
{
  constexpr std::array depressions = {"فيضة",  "فيضه", "فياض",  "فيضات", "روضة", "روضه",
                                      "روضات", "خبرا", "خبراء", "خباري", "خبره", "قاع"};
  constexpr std::array watercourses = {"وادي", "وادى", "شعيب", "شعاب", "شعب", "نهر", "جدول"};
  for (auto const * prefix : depressions)
    if (HasGeographicPrefix(name, prefix))
      return GeographicNameKind::Depression;
  for (auto const * prefix : watercourses)
    if (HasGeographicPrefix(name, prefix))
      return GeographicNameKind::Watercourse;
  return GeographicNameKind::Other;
}
}  // namespace df::mukshat
