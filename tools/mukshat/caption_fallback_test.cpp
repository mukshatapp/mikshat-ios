#include "drape_frontend/mukshat_caption_fallback.hpp"
#include "drape_frontend/mukshat_geographic_presentation.hpp"
#include "drape_frontend/mukshat_map_caption_labels.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <string>
#include <string_view>

int main()
{
  using df::mukshat::MapDetailKind;
  int checks = 0;
  int calls = 0;
  int8_t constexpr arabic = 7;
  assert(df::mukshat::ResolveGenericCaptionLanguage(0, 0, -1, arabic) == arabic);
  assert(df::mukshat::ResolveGenericCaptionLanguage(1, 0, -1, arabic) == 1);
  assert(df::mukshat::ResolveGenericCaptionLanguage(arabic, 0, -1, 1) == arabic);
  assert(df::mukshat::ResolveGenericCaptionLanguage(0, 0, -1, 1) == 1);
  assert(df::mukshat::ResolveGenericCaptionLanguage(-1, 0, -1, arabic) == arabic);
  assert(df::mukshat::ResolveGenericCaptionLanguage(-1, 0, -1, 1) == 1);
  assert(df::mukshat::ResolveGenericCaptionLanguage(0, 0, -1, -1) == -1);
  assert(df::mukshat::ResolveGenericCaptionLanguage(1, 0, -1, -1) == 1);
  checks += 8;
  auto const localize = [&calls](std::string_view type)
  {
    ++calls;
    return std::string(df::mukshat::ArabicMapCaptionForType(type));
  };
  for (auto const kind : {MapDetailKind::IntermittentStream, MapDetailKind::DirtRoad, MapDetailKind::Scrub,
                         MapDetailKind::Other, MapDetailKind::PowerLine})
  {
    for (auto const * actualName : {"شعيب أم جرفن", "طريق القصيم", "فيضة الهيل", "أيكة", "Wadi Hanifa", "Track", "Stream", "Copse"})
    {
      std::string main = actualName;
      std::string const aux = "اسم بديل";
      int8_t mainLang = 3;
      auto const beforeCalls = calls;
      assert(!df::mukshat::PopulateUnnamedCaption(kind, arabic, arabic, main, aux, mainLang, localize));
      assert(main == actualName && aux == "اسم بديل" && mainLang == 3 && calls == beforeCalls);
      checks += 5;
    }
    for (int8_t const lang : {int8_t(0), int8_t(1), int8_t(2)})
    {
      std::string main;
      std::string const aux;
      int8_t mainLang = -1;
      auto const beforeCalls = calls;
      assert(!df::mukshat::PopulateUnnamedCaption(kind, lang, arabic, main, aux, mainLang, localize));
      assert(main.empty() && aux.empty() && mainLang == -1 && calls == beforeCalls);
      checks += 5;
    }
    std::string main;
    std::string const aux = "Actual selected auxiliary name";
    int8_t mainLang = 9;
    auto const beforeCalls = calls;
    assert(!df::mukshat::PopulateUnnamedCaption(kind, arabic, arabic, main, aux, mainLang, localize));
    assert(main.empty() && aux == "Actual selected auxiliary name" && mainLang == 9 && calls == beforeCalls);
    checks += 5;
  }
  for (auto const kind : {MapDetailKind::IntermittentStream, MapDetailKind::DirtRoad, MapDetailKind::Scrub})
  {
    std::string main;
    std::string const aux;
    int8_t mainLang = -1;
    assert(df::mukshat::PopulateUnnamedCaption(kind, arabic, arabic, main, aux, mainLang, localize));
    assert(main == localize(df::mukshat::GenericCaptionType(kind)) && mainLang == arabic && aux.empty());
    checks += 4;
    main.clear();
    mainLang = -1;
    assert(!df::mukshat::PopulateUnnamedCaption(kind, arabic, arabic, main, aux, mainLang,
                                              [](std::string_view) { return std::string(); }));
    assert(main.empty() && mainLang == -1);
    checks += 3;
  }
  {
    // Reproduce the previous callback contract with the real English base
    // type value. An Arabic map-language hint cannot turn an English UI
    // resource lookup into an Arabic caption.
    std::string oldMain;
    std::string const aux;
    int8_t oldLang = -1;
    assert(df::mukshat::PopulateUnnamedCaption(MapDetailKind::DirtRoad, arabic, arabic, oldMain, aux, oldLang,
                                               [](std::string_view) { return std::string("Track"); }));
    assert(oldMain == "Track" && oldLang == arabic);
    std::string fixedMain;
    int8_t fixedLang = -1;
    assert(df::mukshat::PopulateUnnamedCaption(MapDetailKind::DirtRoad, arabic, arabic, fixedMain, aux, fixedLang,
                                               localize));
    assert(fixedMain == "طريق ترابي" && fixedLang == arabic);
    checks += 4;
  }
  // Counterexample: Android UI resources may be English while local Saudi
  // map labels are Arabic. Map captions must not use that UI-localized value.
  for (auto const kind : {MapDetailKind::IntermittentStream, MapDetailKind::DirtRoad, MapDetailKind::Scrub})
  {
    std::string main;
    std::string const aux;
    int8_t mainLang = -1;
    auto const localArabic = df::mukshat::ResolveGenericCaptionLanguage(0, 0, -1, arabic);
    assert(df::mukshat::PopulateUnnamedCaption(kind, localArabic, arabic, main, aux, mainLang, localize));
    assert(main == df::mukshat::ArabicMapCaptionForType(df::mukshat::GenericCaptionType(kind)));
    assert(main != "Track" && main != "Stream" && main != "Copse");
    checks += 3;
    main.clear();
    mainLang = -1;
    assert(!df::mukshat::PopulateUnnamedCaption(kind, 1, arabic, main, aux, mainLang, localize));
    assert(main.empty() && mainLang == -1);
    checks += 2;
  }
  assert(df::mukshat::ArabicMapCaptionForType("waterway-stream-intermittent") == "مسيل");
  assert(df::mukshat::ArabicMapCaptionForType("highway-track") == "طريق ترابي");
  assert(df::mukshat::ArabicMapCaptionForType("natural-scrub") == "فيضة");
  assert(df::mukshat::ArabicMapCaptionForType("unrelated-type").empty());
  checks += 4;
  for (auto const kind : {MapDetailKind::Other, MapDetailKind::PowerLine})
  {
    std::string main;
    std::string const aux;
    int8_t mainLang = -1;
    auto const beforeCalls = calls;
    assert(!df::mukshat::PopulateUnnamedCaption(kind, arabic, arabic, main, aux, mainLang, localize));
    assert(main.empty() && mainLang == -1 && calls == beforeCalls);
    checks += 4;
  }
  assert(std::abs(df::mukshat::kCaptionSizeFactor / df::mukshat::kPreviousCaptionSizeFactor - 1.15f) < 1e-6f);
  assert(std::abs(df::mukshat::kCaptionIncrementFactor - 1.15f) < 1e-6f);
  checks += 2;
  std::cout << "PASS: " << checks << " caption preservation, locale, generic fallback and +15% font checks\n";
}
