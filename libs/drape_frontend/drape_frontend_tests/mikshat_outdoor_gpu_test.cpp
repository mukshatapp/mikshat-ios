#include "testing/testing.hpp"

#include "drape_frontend/apply_feature_functors.hpp"
#include "drape_frontend/apply_feature_params.hpp"
#include "drape_frontend/drape_frontend_tests/shape_test_fixture.hpp"
#include "drape_frontend/gui/ruler_helper.hpp"
#include "drape_frontend/render_state_extension.hpp"
#include "drape_frontend/stylist.hpp"
#include "drape_frontend/tile_utils.hpp"
#include "drape_frontend/visual_params.hpp"

#include "indexer/classificator.hpp"
#include "indexer/classificator_loader.hpp"
#include "indexer/data_source.hpp"
#include "indexer/feature.hpp"
#include "indexer/feature_algo.hpp"
#include "indexer/ftypes_matcher.hpp"
#include "indexer/map_style_reader.hpp"
#include "indexer/mikshat_map_visibility.hpp"
#include "indexer/transliteration_loader.hpp"

#include "platform/local_country_file.hpp"

#include "geometry/mercator.hpp"

#include <QtCore/QDir>
#include <QtGui/QColor>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <functional>
#include <iostream>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace mikshat_outdoor_gpu_test
{
namespace
{
uint32_t constexpr kWidth = 1024;
uint32_t constexpr kHeight = 768;
double constexpr kVisualScale = 3.0;

std::string RequiredEnvironment(char const * name)
{
  char const * value = std::getenv(name);
  TEST(value && *value, ("GPU evidence requires the actual fixture/artifact directory", name));
  return value;
}

class ActualMap
{
public:
  explicit ActualMap(std::string const & path)
  {
    auto file = platform::LocalCountryFile::MakeTemporary(path);
    file.SyncWithDisk();
    auto const registered = m_source.RegisterMap(file);
    TEST_EQUAL(registered.second, MwmSet::RegResult::Success, (path));
    m_loader = std::make_unique<FeaturesLoaderGuard>(m_source, registered.first);
  }

  std::unique_ptr<FeatureType> Get(uint32_t index) const
  {
    auto feature = m_loader->GetFeatureByIndex(index);
    TEST(feature, (index));
    return feature;
  }

private:
  FrozenDataSource m_source;
  std::unique_ptr<FeaturesLoaderGuard> m_loader;
};

class OutdoorGpuFixture
{
public:
  OutdoorGpuFixture() : m_originalStyle(GetStyleReader().GetCurrentStyle())
  {
    InitTransliterationInstanceWithDefaultDirs();
    classificator::Load();
    classificator::EnsureStyleLoaded(MapStyleDefaultLight);
    GetStyleReader().SetCurrentStyle(MapStyleDefaultLight);
    df::VisualParams::Init(kVisualScale, df::CalculateTileSize(kWidth, kHeight));
  }

  ~OutdoorGpuFixture()
  {
    GetStyleReader().SetCurrentStyle(m_originalStyle);
    df::VisualParams::Init(1.0, 1024);
  }

private:
  MapStyle const m_originalStyle;
};

ScreenBase ScreenFor(m2::PointD const & center, double rulerMetres)
{
  // Stay strictly within a ruler interval; its upper endpoint belongs to the following interval.
  double const measuredMetres = rulerMetres * 0.995;
  auto const east = mercator::GetSmPoint(center, measuredMetres, 0.0);
  ScreenBase screen;
  screen.OnSize(0, 0, kWidth, kHeight);
  screen.SetFromParams(center, 0.0, (east.x - center.x) / (60.0 * kVisualScale));
  TEST_EQUAL(gui::RulerHelper::GetMetricRulerDistance(screen), rulerMetres, (center));
  return screen;
}

df::ApplyFeatureParams ParamsFor(ScreenBase const & screen, df::test_support::ShapeTestFixture & fixture)
{
  df::ApplyFeatureParams params;
  params.Init(df::GetTileKeyByPoint(screen.GlobalRect().GlobalCenter(), df::GetDrawTileScale(screen)));
  // The fixture isolates one feature in a viewport, rather than assembling a full tile scene.
  params.m_tileRect = screen.GlobalRect().GetGlobalRect();
  params.m_currentScaleGtoP = 1.0 / screen.GetScale();
  params.m_minSegmentSqrLength = std::pow(4.0 * kVisualScale / params.m_currentScaleGtoP, 2.0);
  params.m_insertShape = [&fixture](drape_ptr<df::MapShape> && shape) { fixture.AddShape(std::move(shape)); };
  return params;
}

df::Stylist StyleFor(FeatureType & feature, ScreenBase const & screen)
{
  return df::Stylist(feature, df::GetDrawTileScale(screen), StringUtf8Multilang::GetLangIndex("ar"),
                     MapStyleDefaultLight,
                     feature::GetMikshatOutdoorVisibility(gui::RulerHelper::GetMetricRulerDistance(screen)));
}

using PixelPredicate = std::function<bool(QColor const &)>;

size_t CountPixels(QImage const & image, PixelPredicate const & predicate)
{
  size_t count = 0;
  for (int y = 0; y < image.height(); ++y)
    for (int x = 0; x < image.width(); ++x)
      count += predicate(image.pixelColor(x, y));
  return count;
}

bool IsBlack(QColor const & c)
{
  return std::max({c.red(), c.green(), c.blue()}) < 65;
}
bool IsBrown(QColor const & c)
{
  return c.red() > c.green() && c.green() > c.blue() + 12 && c.red() < 190;
}
bool IsBlue(QColor const & c)
{
  return c.blue() > c.red() + 25 && c.blue() > c.green() + 8;
}
bool IsPurpleBorder(QColor const & c)
{
  return c.blue() > c.red() + 15 && c.red() > c.green() + 20 && c.red() < 195;
}
bool IsLightPurple(QColor const & c)
{
  // Analytic hatching modulates the rule's 0.3 alpha: visible lavender over white
  // can differ by only 2-4 channel values. White and neutral glyph edges still fail.
  return c.blue() > c.red() + 1 && c.red() > c.green() + 1 && c.red() >= 195;
}
bool IsWhite(QColor const & c)
{
  return std::min({c.red(), c.green(), c.blue()}) >= 250;
}

void SaveFrame(QImage const & image, std::string const & name, std::string const & source, uint32_t featureIndex,
               ScreenBase const & screen)
{
  auto const directory = RequiredEnvironment("MIKSHAT_GPU_ARTIFACTS_DIR");
  TEST(QDir().mkpath(QString::fromStdString(directory)), (directory));
  auto const path = directory + "/" + name;
  TEST(image.save(QString::fromStdString(path + ".png"), "PNG"), (path));
  std::unordered_map<QRgb, size_t> histogram;
  for (int y = 0; y < image.height(); ++y)
    for (int x = 0; x < image.width(); ++x)
      ++histogram[image.pixelColor(x, y).rgba()];
  std::vector<std::pair<size_t, QRgb>> frequentColours;
  for (auto const & [colour, count] : histogram)
    frequentColours.emplace_back(count, colour);
  std::sort(frequentColours.rbegin(), frequentColours.rend());
  std::cout << "MIKSHAT_OUTDOOR_GPU_COLOURS " << name;
  for (size_t i = 0; i < std::min<size_t>(10, frequentColours.size()); ++i)
  {
    QColor const colour(frequentColours[i].second);
    std::cout << " (" << colour.red() << ',' << colour.green() << ',' << colour.blue() << ":"
              << frequentColours[i].first << ')';
  }
  std::cout << '\n';
  std::ofstream metadata(path + ".json");
  TEST(metadata.is_open(), (path));
  metadata << "{\"scope\":\"Actual MWM feature, generated light style, production Apply helpers, isolated OpenGL "
              "shader fixture; no map collision, full iOS scene or Metal assertion\",\"source\":\""
           << source << "\",\"feature\":" << featureIndex
           << ",\"rulerMetres\":" << gui::RulerHelper::GetMetricRulerDistance(screen)
           << ",\"drawZoom\":" << df::GetDrawTileScale(screen) << ",\"blackPixels\":" << CountPixels(image, IsBlack)
           << ",\"brownPixels\":" << CountPixels(image, IsBrown) << ",\"bluePixels\":" << CountPixels(image, IsBlue)
           << ",\"purpleBorderPixels\":" << CountPixels(image, IsPurpleBorder)
           << ",\"lightPurplePixels\":" << CountPixels(image, IsLightPurple) << "}\n";
  metadata.close();
  TEST(!metadata.fail(), (path));
  std::cout << "MIKSHAT_OUTDOOR_GPU_FRAME " << path << ".png\n";
}

QImage RenderCaption(FeatureType & feature, ScreenBase const & screen)
{
  auto const style = StyleFor(feature, screen);
  df::test_support::ShapeTestFixture fixture;
  fixture.SetScreen(screen);
  fixture.Render("Actual MWM caption / generated style", kWidth, kHeight, [&](auto & f)
  {
    auto const params = ParamsFor(screen, f);
    df::ApplyPointFeature apply(params, feature, style.m_captionDescriptor);
    apply.ProcessPointRules(nullptr, style.m_captionRule, nullptr, feature::GetCenter(feature), f.GetTextureManager());
  });
  return fixture.GetLastImage();
}

// Sample the genuine path in pixel space. A dashed line can have the correct colour/count while leaving gaps.
void CheckSolidPath(QImage const & image, FeatureType & feature, ScreenBase const & screen,
                    PixelPredicate const & predicate)
{
  std::vector<m2::PointD> points;
  feature.ForEachPoint([&](auto const & point) { points.push_back(screen.GtoP(point)); }, FeatureType::BEST_GEOMETRY);
  size_t samples = 0;
  size_t covered = 0;
  for (size_t i = 1; i < points.size(); ++i)
  {
    auto const & a = points[i - 1];
    auto const & b = points[i];
    int const steps = std::max(1, static_cast<int>(std::ceil(a.Length(b) * 2.0)));
    for (int step = 0; step < steps; ++step)
    {
      auto const p = a + (b - a) * (static_cast<double>(step) / steps);
      if (p.x < 5 || p.y < 5 || p.x >= image.width() - 5 || p.y >= image.height() - 5)
        continue;
      ++samples;
      bool found = false;
      for (int dy = -2; dy <= 2; ++dy)
        for (int dx = -2; dx <= 2; ++dx)
          found = found || predicate(image.pixelColor(static_cast<int>(std::round(p.x)) + dx,
                                                      static_cast<int>(std::round(p.y)) + dy));
      covered += found;
    }
  }
  TEST_GREATER(samples, 10, ("The authentic path must occupy enough pixels to test continuity"));
  TEST_GREATER_OR_EQUAL(covered * 100, samples * 90, ("Visible gaps in the supposedly solid path", samples, covered));
}
}  // namespace

UNIT_CLASS_TEST(OutdoorGpuFixture, MikshatOutdoorGPU_ActualLocalityCaptions15km)
{
  ActualMap const north(RequiredEnvironment("MIKSHAT_SUPPLEMENTARY_MAPS_DIR") + "/desert-ksa-north.mwm");
  std::array<uint32_t, 4> constexpr indices = {17844, 17877, 17886, 17896};
  for (auto const index : indices)
  {
    auto feature = north.Get(index);
    TEST(feature::TypesHolder(*feature).Has(classif().GetTypeByPath({"place", "locality"})), (index));
    auto const screen = ScreenFor(feature->GetCenter(), 15000.0);
    auto const style = StyleFor(*feature, screen);
    TEST(style.m_captionRule && style.m_captionRule->primary, (index));
    TEST_EQUAL(style.m_captionRule->primary->color & 0xFFFFFF, 0, (index));
    TEST_GREATER_OR_EQUAL(style.m_captionRule->primary->height, 14, (index));
    auto const image = RenderCaption(*feature, screen);
    SaveFrame(image, "place-locality-" + std::to_string(index) + "-15000m", "desert-ksa-north", index, screen);
    TEST_GREATER(CountPixels(image, IsBlack), 80, ("Actual Arabic glyphs must be visible in black", index));

    auto const outside = ScreenFor(feature->GetCenter(), 20000.0);
    TEST(!StyleFor(*feature, outside).m_captionRule, ("The same real locality must not appear at 20 km", index));
  }
}

UNIT_CLASS_TEST(OutdoorGpuFixture, MikshatOutdoorGPU_ActualDirtAndWadi20km)
{
  ActualMap const south(RequiredEnvironment("MIKSHAT_SUPPLEMENTARY_MAPS_DIR") + "/desert-ksa-south.mwm");
  for (auto const index : {89455u, 65436u})
  {
    bool const dirt = index == 89455;
    auto feature = south.Get(index);
    TEST_EQUAL(feature->GetGeomType(), feature::GeomType::Line, (index));
    TEST(dirt ? ftypes::IsUnpavedRoad(feature::TypesHolder(*feature))
              : feature::TypesHolder(*feature).Has(classif().GetTypeByPath({"waterway", "river"})),
         (index));
    auto const screen = ScreenFor(feature::GetCenter(*feature), 20000.0);
    auto const style = StyleFor(*feature, screen);
    TEST(!style.m_lineRules.empty(), (index));
    for (auto const rule : style.m_lineRules)
      TEST(!rule->dashdot, ("Actual dirt/wadi path must be continuous", index));
    df::test_support::ShapeTestFixture fixture;
    fixture.SetScreen(screen);
    fixture.Render("Actual MWM dirt/wadi / generated style", kWidth, kHeight, [&](auto & f)
    {
      auto const params = ParamsFor(screen, f);
      feature::PrepareMikshatOverviewGeometry(*feature, df::GetDrawTileScale(screen));
      df::ApplyLineFeatureGeometry apply(params, *feature, {}, false /* isIsoline */);
      apply.BuildGeometry(df::GetDrawTileScale(screen));
      TEST(apply.HasGeometry(), (index));
      apply.ProcessLineRules(style.m_lineRules);
    });
    auto const & image = fixture.GetLastImage();
    auto const predicate = dirt ? IsBrown : IsBlue;
    SaveFrame(image, std::string(dirt ? "highway-track-" : "waterway-river-") + std::to_string(index) + "-20000m",
              "desert-ksa-south", index, screen);
    TEST_GREATER(CountPixels(image, predicate), 10, ("An empty or wrongly coloured frame is not evidence", index));
    CheckSolidPath(image, *feature, screen, predicate);
    auto const outside = ScreenFor(feature::GetCenter(*feature), 50000.0);
    TEST(StyleFor(*feature, outside).m_lineRules.empty(), ("Outdoor paths share the 20 km outer threshold", index));
  }
}

UNIT_CLASS_TEST(OutdoorGpuFixture, MikshatOutdoorGPU_ActualProtectedBoundary50To2km)
{
  ActualMap const north(RequiredEnvironment("MIKSHAT_SUPPLEMENTARY_MAPS_DIR") + "/desert-ksa-north.mwm");
  uint32_t constexpr kIndex = 36786;
  auto feature = north.Get(kIndex);
  TEST_EQUAL(feature->GetGeomType(), feature::GeomType::Area, ());
  std::vector<m2::PointD> triangles;
  feature->ForEachTriangle([&](auto const & a, auto const & b, auto const & c)
  { triangles.insert(triangles.end(), {a, b, c}); }, FeatureType::BEST_GEOMETRY);
  TEST(!triangles.empty(), ("The real protected polygon must provide geometry"));
  auto const paths = df::BuildAreaOutlineSplines(triangles, feature->GetLimitRect(FeatureType::BEST_GEOMETRY));
  double longest = 0;
  m2::PointD focus;
  for (auto const & path : paths)
  {
    auto const & points = path->GetPath();
    for (size_t i = 1; i < points.size(); ++i)
      if (double const length = points[i - 1].SquaredLength(points[i]); length > longest)
      {
        longest = length;
        focus = (points[i - 1] + points[i]) / 2.0;
      }
  }
  TEST_GREATER(longest, 0.0, ("An actual boundary segment must be present at the frame centre"));
  size_t overviewFillPixels = 0;
  double overviewWidth = 0;
  for (double const ruler : {50000.0, 20000.0, 15000.0, 2000.0})
  {
    auto const screen = ScreenFor(focus, ruler);
    auto const style = StyleFor(*feature, screen);
    TEST(!style.m_areaOutlineRules.empty(), (ruler));
    TEST(style.m_captionRule && !style.m_captionDescriptor.GetMainText().empty(), (ruler));
    std::cout << "MIKSHAT_OUTDOOR_GPU_AREA_RULES ruler=" << ruler
              << " area=" << (style.m_areaRule ? std::to_string(style.m_areaRule->color) : "none")
              << " hatch=" << (style.m_hatchingRule ? std::to_string(style.m_hatchingRule->color) : "none")
              << " pattern=" << style.m_hatchingPattern << '\n';
    df::test_support::ShapeTestFixture fixture;
    fixture.SetScreen(screen);
    fixture.Render("Actual MWM protected polygon / generated style", kWidth, kHeight, [&](auto & f)
    {
      auto const params = ParamsFor(screen, f);
      df::ApplyAreaFeature apply(params, *feature, style.m_captionDescriptor, false, false, 0, 0, 1.0, true);
      for (size_t i = 0; i < triangles.size(); i += 3)
        apply(triangles[i], triangles[i + 1], triangles[i + 2]);
      TEST(apply.HasGeometry(), (ruler));
      apply.ProcessAreaRules(style, style.m_hatchingPattern, {});
      apply.ProcessAreaOutlines(style.m_areaOutlineRules);
    });
    auto const & image = fixture.GetLastImage();
    SaveFrame(image, "protected-area-36786-" + std::to_string(static_cast<int>(ruler)) + "m", "desert-ksa-north",
              kIndex, screen);
    TEST_GREATER(CountPixels(image, IsPurpleBorder), 50,
                 ("The genuine purple boundary must survive every frame", ruler));
    auto const lightPurple = CountPixels(image, IsLightPurple);
    if (ruler == 50000.0)
    {
      overviewFillPixels = lightPurple;
      overviewWidth = style.m_areaOutlineRules.front()->width;
      TEST_GREATER(lightPurple, 2000, ("An actual light-purple polygon fill must be visible at 50 km"));
    }
    if (ruler == 2000.0)
    {
      TEST(!df::IsProtectedAreaFillVisible(screen), ());
      TEST_GREATER(CountPixels(image, IsWhite), kWidth * kHeight * 9 / 10,
                   ("Close fill must disappear, leaving only edges"));
      TEST_LESS(lightPurple * 3, overviewFillPixels, ("Border antialiasing must not be mistaken for a retained fill"));
      TEST_GREATER(style.m_areaOutlineRules.front()->width, overviewWidth, ("The close boundary must be thicker"));
    }
    else
    {
      TEST(df::IsProtectedAreaFillVisible(screen), (ruler));
      TEST_GREATER(lightPurple, 2000, ("Protected fill is required before the 2 km cutoff", ruler));
    }
  }
}
}  // namespace mikshat_outdoor_gpu_test
