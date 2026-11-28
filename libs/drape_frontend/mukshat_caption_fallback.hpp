#pragma once

#include "drape_frontend/mukshat_detail_visibility.hpp"

#include <cstdint>
#include <string>
#include <string_view>
#include <utility>

namespace df::mukshat
{
inline constexpr std::string_view GenericCaptionType(MapDetailKind kind)
{
  switch (kind)
  {
  case MapDetailKind::IntermittentStream: return "waterway-stream-intermittent";
  case MapDetailKind::DirtRoad: return "highway-track";
  case MapDetailKind::Scrub: return "natural-scrub";
  case MapDetailKind::PowerLine:
  case MapDetailKind::Other: return {};
  }
  return {};
}

// Real selected names and their language hints always take precedence over a
// generic presentation label. The source feature names are never modified.
template <typename Localizer>
bool PopulateUnnamedCaption(MapDetailKind kind, int8_t deviceLang, int8_t arabicLang, std::string & mainText,
                            std::string const & auxText, int8_t & mainTextLang, Localizer const & localize)
{
  if (deviceLang != arabicLang || !mainText.empty() || !auxText.empty())
    return false;
  auto const type = GenericCaptionType(kind);
  if (type.empty())
    return false;
  auto text = localize(type);
  if (text.empty())
    return false;
  mainText = std::move(text);
  mainTextLang = arabicLang;
  return true;
}
}  // namespace df::mukshat
