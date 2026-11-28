#include "drape_frontend/mukshat_caption_fallback.hpp"
#include "drape_frontend/mukshat_geographic_presentation.hpp"

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
    if (type == "waterway-stream-intermittent")
      return std::string("مسيل");
    if (type == "highway-track")
      return std::string("طريق ترابي");
    if (type == "natural-scrub")
      return std::string("فيضة");
    return std::string();
  };
  for (auto const kind : {MapDetailKind::IntermittentStream, MapDetailKind::DirtRoad, MapDetailKind::Scrub,
                         MapDetailKind::Other, MapDetailKind::PowerLine})
  {
    for (auto const * actualName : {"شعيب أم جرفن", "طريق القصيم", "فيضة الهيل", "أيكة", "Wadi Hanifa"})
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
