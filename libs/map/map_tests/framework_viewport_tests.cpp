#include "testing/testing.hpp"

#include "map/framework.hpp"

#include "generator/generator_tests_support/test_feature.hpp"
#include "generator/generator_tests_support/test_mwm_builder.hpp"

#include "search/utils.hpp"

#include "indexer/classificator.hpp"

#include "platform/platform_tests_support/scoped_dir.hpp"

#include "geometry/any_rect2d.hpp"
#include "geometry/mercator.hpp"

#include "base/file_name_utils.hpp"
#include "base/math.hpp"

namespace framework_viewport_tests
{
namespace
{
class TestFramework final : public Framework
{
public:
  TestFramework() : Framework({}, false /* loadMaps */) {}

  void SetViewport(ScreenBase const & screen, m2::RectD const & visibleViewport)
  {
    m_currentModelView = screen;
    m_visibleViewport = visibleViewport;
  }
};
}  // namespace

UNIT_TEST(Framework_GetViewportCenter)
{
  m2::RectD const pixelRect(0.0, 0.0, 1000.0, 1000.0);
  m2::RectD const visibleViewport(0.0, 0.0, 1000.0, 700.0);
  m2::PointD const target(185.0, 5.0);
  double constexpr kEps = 1e-7;

  TestFramework framework;
  for (bool const perspective : {false, true})
  {
    ScreenBase screen;
    screen.SetFromRects(m2::AnyRectD(m2::RectD(170.0, -10.0, 190.0, 10.0)), pixelRect);
    if (perspective)
      screen.ApplyPerspective(math::pi4, math::pi4, math::pi / 3.0);
    screen.MatchGandP3d(target, visibleViewport.Center());

    framework.SetViewport(screen, visibleViewport);
    auto const actual = framework.GetViewportCenter();
    TEST_ALMOST_EQUAL_ABS(actual.x, mercator::WrapX(target.x), kEps, (perspective));
    TEST_ALMOST_EQUAL_ABS(actual.y, target.y, kEps, (perspective));
  }
}

UNIT_TEST(Framework_SupplementaryMapCanToggleWithOutstandingReaderWithoutDeletingSource)
{
  auto const directory = base::JoinPath(GetPlatform().WritableDir(), "supplementary-map-lifecycle");
  // Keep the source for every lifecycle assertion, then clean it after Framework releases its readers.
  platform::tests_support::ScopedDirCleanup cleanup(directory);
  auto const path = base::JoinPath(directory, "supplementary-test.mwm");
  auto file = platform::LocalCountryFile::MakeTemporary(path);
  Framework framework({}, false /* loadMaps */);
  {
    generator::tests_support::TestMwmBuilder builder(file, feature::DataHeader::MapType::Country);
    generator::tests_support::TestPOI cafe({0, 0}, "Supplementary cafe", "en");
    cafe.SetTypes({{"amenity", "cafe"}});
    builder.Add(cafe);
    builder.Finish();
  }

  m2::RectD const viewport(-1, -1, 1, 1);
  auto const countFeatures = [&]
  {
    size_t count = 0;
    framework.GetDataSource().ForEachFeatureIDInRect([&](auto const &) { ++count; }, viewport, 17);
    return count;
  };
  auto const countCategoryMatches = [&]
  {
    size_t count = 0;
    search::ForEachOfTypesInRect(framework.GetDataSource(), {classif().GetTypeByPath({"amenity", "cafe"})}, viewport,
                                 [&](auto const &) { ++count; });
    return count;
  };

  TEST(framework.SetSupplementaryMapEnabled(file, true), ());
  TEST(framework.IsCountryLoadedByName("supplementary-test"), ());
  TEST_EQUAL(countFeatures(), 1, ());
  TEST_EQUAL(countCategoryMatches(), 1, ());
  auto const id = framework.GetDataSource().GetMwmIdByCountryFile(file.GetCountryFile());
  {
    auto reader = framework.GetDataSource().GetMwmHandleById(id);
    TEST(reader.IsAlive(), ());
    TEST(framework.SetSupplementaryMapEnabled(file, false), ());
    TEST(!framework.IsCountryLoadedByName("supplementary-test"), ());
    TEST(GetPlatform().IsFileExistsByFullPath(path), ());
    TEST_EQUAL(countFeatures(), 0, ());
    TEST_EQUAL(countCategoryMatches(), 0, ());

    // Re-enabling before the old reader exits must use the map's actual data version.
    TEST(framework.SetSupplementaryMapEnabled(file, true), ());
    TEST(framework.IsCountryLoadedByName("supplementary-test"), ());
    TEST_EQUAL(countFeatures(), 1, ());
    TEST_EQUAL(countCategoryMatches(), 1, ());
  }
  TEST(framework.SetSupplementaryMapEnabled(file, false), ());
  TEST(!framework.IsCountryLoadedByName("supplementary-test"), ());
  TEST(GetPlatform().IsFileExistsByFullPath(path), ());
  TEST(framework.SetSupplementaryMapEnabled(file, true), ());
  TEST(framework.SetSupplementaryMapEnabled(file, false), ());
  TEST(!framework.IsCountryLoadedByName("supplementary-test"), ());
  TEST(GetPlatform().IsFileExistsByFullPath(path), ());
}

UNIT_TEST(Framework_SupplementaryMapsCannotReplaceCoreWorldOrDownloaderCountries)
{
  Framework framework({}, false /* loadMaps */);
  for (auto const & name : {"World", "WorldCoasts", "Germany"})
  {
    platform::LocalCountryFile const file(GetPlatform().ResourcesDir(), platform::CountryFile(name), 0);
    TEST(!framework.SetSupplementaryMapEnabled(file, true), (name));
    TEST(!framework.SetSupplementaryMapEnabled(file, false), (name));
  }
}
}  // namespace framework_viewport_tests
