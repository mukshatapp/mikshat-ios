// The Python runner inserts the exact production renderer function here.
// Only its external selected-name/region providers are fixtures.
#include "drape_frontend/mukshat_caption_fallback.hpp"
#include "drape_frontend/mukshat_geographic_presentation.hpp"
#include "drape_frontend/mukshat_map_caption_labels.hpp"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <string_view>

#define ASSERT(condition, message) assert(condition)

struct StringUtf8Multilang
{
  static int8_t GetLangIndex(char const *) { return 7; }
  static constexpr int8_t kDefaultCode = 0;
  static constexpr int8_t kUnsupportedLanguageCode = -1;
};

namespace feature
{
enum class GeomType
{
  Point,
  Line,
  Area
};
struct NameParamsOut
{
  std::string_view primary;
  std::string_view secondary;
  std::string transliterated;
  int8_t primaryLang = StringUtf8Multilang::kUnsupportedLanguageCode;
  int8_t secondaryLang = StringUtf8Multilang::kUnsupportedLanguageCode;
  std::string_view GetPrimary() const
  {
    assert(primary.empty() || transliterated.empty());
    return !primary.empty() ? primary : std::string_view(transliterated);
  }
};
int8_t GetRegionLang(int8_t region)
{
  return region;
}
}  // namespace feature
namespace scales
{
int GetUpperWorldScale()
{
  return 9;
}
}  // namespace scales

struct RegionInfo
{
  int8_t GetRegionData() const { return 7; }
};
struct MwmId
{
  RegionInfo const * GetInfo() const
  {
    static RegionInfo const region;
    return &region;
  }
};
struct FeatureId
{
  MwmId m_mwmId;
};

class FeatureType
{
public:
  df::mukshat::MapDetailKind kind = df::mukshat::MapDetailKind::DirtRoad;
  std::string primary;
  std::string secondary;
  std::string transliterated;
  std::string houseNumber;
  FeatureId GetID() const { return {}; }
  void GetPreferredNames(bool, int8_t, feature::NameParamsOut & out) const
  {
    out.primary = primary;
    out.secondary = secondary;
    out.transliterated = transliterated;
    out.primaryLang = primary.empty() ? int8_t(2) : StringUtf8Multilang::kDefaultCode;
    out.secondaryLang = 3;
  }
  void GetReadableName(bool translit, int8_t lang, feature::NameParamsOut & out) const
  {
    GetPreferredNames(translit, lang, out);
    out.secondary = {};
  }
  std::string GetHouseNumber() const { return houseNumber; }
};

namespace df::mukshat
{
inline MapDetailKind ClassifyMapDetail(FeatureType const & feature)
{
  return feature.kind;
}
}  // namespace df::mukshat

namespace df
{
class CaptionDescription
{
public:
  void Init(FeatureType &, int8_t, int, feature::GeomType, bool);
  std::string m_mainText;
  std::string m_auxText;
  std::string m_houseNumberText;
  int8_t m_mwmRegionLang = -1;
  int8_t m_mainTextLang = -1;
  int8_t m_auxTextLang = -1;
};

// INSERT_ACTUAL_CAPTION_INIT
}  // namespace df

int main()
{
  int cases = 0;
  for (auto const geometry : {feature::GeomType::Point, feature::GeomType::Line, feature::GeomType::Area})
    for (int const zoom : {4, 9, 11, 13, 17})
      for (int8_t const lang : {int8_t(-1), int8_t(0), int8_t(1), int8_t(7)})
        for (bool const auxExists : {false, true})
        {
          // Unnamed type features (including track/scrub/stream/river) have
          // empty selected-name providers. No category-to-caption path remains.
          FeatureType unnamed;
          df::CaptionDescription empty;
          empty.Init(unnamed, lang, zoom, geometry, auxExists);
          assert(empty.m_mainText.empty() && empty.m_auxText.empty());
          ++cases;
          for (auto const * name : {"طريق ترابي", "فيضة", "مسيل", "نهر", "Track", "Stream", "Copse", "شعيب أم جرفن",
                                    "فيضة الهيل", "نهر النيل", "Wadi Hanifa"})
          {
            FeatureType named;
            named.primary = name;
            named.secondary = "Secondary name";
            df::CaptionDescription caption;
            caption.Init(named, lang, zoom, geometry, auxExists);
            assert(caption.m_mainText == name);
            assert(caption.m_mainTextLang == 7);  // Default name resolves regional Arabic.
            bool const usesAux =
                zoom > scales::GetUpperWorldScale() && (auxExists || geometry == feature::GeomType::Line);
            assert(caption.m_auxText == (usesAux ? "Secondary name" : ""));
            ++cases;
          }
          FeatureType transliterated;
          transliterated.transliterated = "Transliterated name";
          df::CaptionDescription caption;
          caption.Init(transliterated, lang, zoom, geometry, auxExists);
          assert(caption.m_mainText == "Transliterated name" && caption.m_mainTextLang == 2);
          ++cases;
        }
  // Existing low-world text cap, house-number and font behavior remain exercised.
  FeatureType longName;
  longName.primary = std::string(60, 'A');
  df::CaptionDescription low;
  low.Init(longName, 7, 4, feature::GeomType::Point, false);
  assert(low.m_mainText.empty());
  FeatureType building;
  building.primary = "12";
  building.houseNumber = "12";
  df::CaptionDescription house;
  house.Init(building, 7, 17, feature::GeomType::Point, true);
  assert(house.m_houseNumberText == "12" && house.m_mainText.empty());
  assert(std::abs(df::mukshat::kCaptionSizeFactor / df::mukshat::kPreviousCaptionSizeFactor - 1.15f) < 1e-6f);
  assert(std::abs(df::mukshat::kCaptionIncrementFactor - 1.15f) < 1e-6f);
  std::cout << "PASS: " << cases << " actual renderer selected-name cases; unnamed captions stay empty, "
            << "named literals/transliteration/auxiliary names preserved; prior label size +15% unchanged\n";
}
