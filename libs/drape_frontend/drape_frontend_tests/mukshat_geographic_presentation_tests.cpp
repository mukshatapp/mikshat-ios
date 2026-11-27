#include "drape_frontend/mukshat_geographic_presentation.hpp"

#include <iostream>
#include <stdexcept>
#include <string>

#if defined(MUKSHAT_GEOGRAPHY_STANDALONE)
namespace
{
size_t checks = 0;
void Check(bool result, char const * expression, int line)
{
  ++checks;
  if (!result)
    throw std::runtime_error(std::string(expression) + " at line " + std::to_string(line));
}
}  // namespace
#define UNIT_TEST(name)                       void name()
#define TEST(expression, message)             Check(bool(expression), #expression, __LINE__)
#define TEST_EQUAL(actual, expected, message) Check((actual) == (expected), #actual " == " #expected, __LINE__)
#else
#include "testing/testing.hpp"
#endif

namespace
{
using df::mukshat::ClassifyGeographicName;
using df::mukshat::GeographicNameKind;

UNIT_TEST(Mukshat_RealSupplementalLandformNames)
{
  for (auto const * name :
       {"فيضة الهيل", "فيضة الطرفا", "فيضه المشاحنة", "فياض العوشزية", "فيضات الدبدبة", "روضة مريزيق", "روضه التنهات",
        "روضات الخفس", "خباري الحسنة", "خبرا طلق", "خبراء نياب", "خبره العوشزية", "قاع المري"})
    TEST_EQUAL(ClassifyGeographicName(name), GeographicNameKind::Depression, (name));
  for (auto const * name : {"وادي فاطمة", "وادي أم السلم", "وادى حنيفة", "شعيب أم جرفن", "شعاب الحلوة", "شعب دغبج",
                            "نهر النيل", "جدول الماء"})
    TEST_EQUAL(ClassifyGeographicName(name), GeographicNameKind::Watercourse, (name));
}

UNIT_TEST(Mukshat_NameWordBoundaries)
{
  for (auto const * name : {"الرياض", "جبل فيضة", "محطة وادي", "فيضان", "فيضانات", "روضةالعلم", "واديان", "جدولي",
                            "روضي", "Al Fayda", "Riyadh", "", " ", "  فيضة الهيل"})
    TEST_EQUAL(ClassifyGeographicName(name), GeographicNameKind::Other, (name));
  TEST_EQUAL(ClassifyGeographicName("فيضة"), GeographicNameKind::Depression, ());
  TEST_EQUAL(ClassifyGeographicName("وادي"), GeographicNameKind::Watercourse, ());
  TEST_EQUAL(ClassifyGeographicName("روضة التنهات"), GeographicNameKind::Depression, ());
  TEST_EQUAL(ClassifyGeographicName("شعيب\tالماء"), GeographicNameKind::Watercourse, ());
}

UNIT_TEST(Mukshat_CaptionAndBorderPresentation)
{
  TEST(df::mukshat::kCaptionSizeFactor > 1.0f, ());
  TEST(df::mukshat::kCaptionSizeFactor <= 1.25f, ());
  // Lowest reserve BG-top priority1 is0.1 renderer depth units above landcover.
  // Waterway priority10 is1.0 units above landcover; a border stays below it.
  TEST(df::mukshat::kReserveBorderDepthOffset > 0.0, ());
  TEST(0.1 + df::mukshat::kReserveBorderDepthOffset < 1.0, ());
}
}  // namespace

#if defined(MUKSHAT_GEOGRAPHY_STANDALONE)
int main()
{
  Mukshat_RealSupplementalLandformNames();
  Mukshat_NameWordBoundaries();
  Mukshat_CaptionAndBorderPresentation();
  std::cout << "PASS: " << checks << " geographic-name and presentation checks\n";
}
#endif
