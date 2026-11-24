#include "testing/testing.hpp"

#include "drape_frontend/apply_feature_functors.hpp"
#include "drape_frontend/apply_feature_params.hpp"
#include "drape_frontend/area_shape.hpp"
#include "drape_frontend/drape_frontend_tests/visual_params_fixture.hpp"
#include "drape_frontend/line_shape.hpp"
#include "drape_frontend/render_group.hpp"
#include "drape_frontend/render_state_extension.hpp"

#include "indexer/feature.hpp"

#include "shaders/programs.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <set>
#include <string>

namespace
{
double Frac(double v)
{
  return v - std::floor(v);
}

// Reproduces the GPU pattern UV that AreaShape::DrawPatternArea bakes into the vertex buffer:
//   maxU * (worldCoord - anchor),  maxU = baseGtoPScale / maskSizePx.
double HatchUV(double worldCoord, double bboxMin, uint32_t maskSizePx, double baseGtoPScale)
{
  double const maxU = baseGtoPScale / maskSizePx;
  return maxU * (worldCoord - df::CalcHatchingPhaseAnchor(bboxMin, maskSizePx, baseGtoPScale));
}

using Point = m2::PointD;
using OutlineEdge = std::pair<Point, Point>;
using df::test_support::VisualParamsFixture;

OutlineEdge MakeEdge(Point const & a, Point const & b)
{
  return {std::min(a, b), std::max(a, b)};
}

std::set<OutlineEdge> OutlineEdges(std::vector<m2::SharedSpline> const & splines)
{
  std::set<OutlineEdge> edges;
  for (auto const & spline : splines)
  {
    auto const & path = spline->GetPath();
    for (size_t i = 1; i < path.size(); ++i)
      TEST(edges.insert(MakeEdge(path[i - 1], path[i])).second, ("Repeated boundary edge", path));
  }
  return edges;
}

void AppendQuad(std::vector<Point> & triangles, Point const & a, Point const & b, Point const & c, Point const & d)
{
  triangles.insert(triangles.end(), {a, b, c, a, c, d});
}
}  // namespace

// The analytic hatch repeats with mod() over the lattice coordinate, so only its fractional part (the
// phase) is visible. The phase must be a function of the world coordinate alone — independent of how a
// feature happens to be clipped into per-tile bounding boxes — otherwise the pattern snaps/shifts and
// breaks at tile seams when geometry is re-tiled or the LOD changes (issue #12804).
UNIT_TEST(HatchingPhaseAnchor_StableAcrossTileClipping)
{
  uint32_t const kMaskPx = 16;                                      // analytic hatch tile is 16px (kHatchTilePx)
  double const kBaseGtoP = 4096.0;                                  // pixels per mercator unit at some zoom level
  double const kPeriod = static_cast<double>(kMaskPx) / kBaseGtoP;  // world units per mask repeat

  // A world vertex lying on the shared edge of two adjacent tiles.
  double const worldX = 123.4567;

  // The two tiles clip the same feature differently => arbitrary, non-period-aligned bbox mins.
  double const bboxMinA = 123.40;
  double const bboxMinB = 122.91;

  double const anchorA = df::CalcHatchingPhaseAnchor(bboxMinA, kMaskPx, kBaseGtoP);
  double const anchorB = df::CalcHatchingPhaseAnchor(bboxMinB, kMaskPx, kBaseGtoP);

  // Anchor sits on the global period grid, just below the bbox min (so UVs stay small for float precision).
  TEST(anchorA <= bboxMinA && bboxMinA - anchorA < kPeriod, (anchorA, bboxMinA, kPeriod));
  TEST(anchorB <= bboxMinB && bboxMinB - anchorB < kPeriod, (anchorB, bboxMinB, kPeriod));

  // The invariant: the sampled texel (UV mod 1) for the shared vertex matches across both tiles.
  double const uvA = HatchUV(worldX, bboxMinA, kMaskPx, kBaseGtoP);
  double const uvB = HatchUV(worldX, bboxMinB, kMaskPx, kBaseGtoP);
  TEST_ALMOST_EQUAL_ABS(Frac(uvA), Frac(uvB), 1e-5, (uvA, uvB));
}

// At a fixed scale, the phase depends only on the world coordinate, including at negative coordinates.
UNIT_TEST(HatchingPhaseAnchor_IndependentOfBBoxAtFixedScale)
{
  uint32_t const kMaskPx = 16;
  double const kBaseGtoP = 256.0;
  double const worldX = -57.318;  // negative coordinate => floor() must round toward -inf, not toward 0

  // Many distinct clip bboxes, all containing worldX, must yield the same phase.
  double const refUV = HatchUV(worldX, worldX - 0.001, kMaskPx, kBaseGtoP);
  for (double offset : {0.0123, 0.5, 1.7, 13.0, 100.25})
  {
    double const bboxMin = worldX - offset;
    double const uv = HatchUV(worldX, bboxMin, kMaskPx, kBaseGtoP);
    TEST_ALMOST_EQUAL_ABS(Frac(uv), Frac(refUV), 1e-4, (offset, uv, refUV));
  }
}

// Within a DepthLayer, render groups draw in dp::RenderState order (RenderGroupComparator falls back to
// RenderState::operator<, which for a shared layer and blending compares the gpu::Program value). The
// analytic solid-fill patterns (stipple/speckle/grid) are background fills, but translucent geometry still writes
// depth across its whole shape (depth-write is bound to the depth test), including its transparent pixels such
// as the gaps of a hatch or a dashed line. So a fill whose group is drawn AFTER such geometry is depth-culled
// wherever they overlap -- e.g. a landcover fill under a protected-area hatch, or a beach under a path. The
// fills must therefore sort BEFORE every program that can draw translucent geometry over them.
UNIT_TEST(AreaPatterns_SolidFillsDrawBeforeTranslucentGeometry)
{
  auto const state = [](gpu::Program p) { return df::CreateRenderState(p, df::DepthLayer::GeometryLayer); };

  // gpu::DebugPrint returns string_view, which base::Message can't concatenate; wrap names in std::string.
  for (auto fill : {gpu::Program::AreaStipple, gpu::Program::AreaSpeckle, gpu::Program::AreaGrid})
    for (auto overlay :
         {gpu::Program::Line, gpu::Program::DashedLine, gpu::Program::PathSymbol, gpu::Program::TransparentArea,
          gpu::Program::CapJoin, gpu::Program::HatchingArea, gpu::Program::HatchingAreaDash})
      TEST(state(fill) < state(overlay),
           (std::string{DebugPrint(fill)}, "must sort before", std::string{DebugPrint(overlay)}));
}

UNIT_TEST(ProtectedAreaFill_SeparateBatchesPreserveProgramOrder)
{
  using namespace df;
  auto const regular = CreateRenderState(gpu::Program::HatchingArea, DepthLayer::GeometryLayer);
  auto const protectedFill = CreateRenderState(gpu::Program::HatchingArea, DepthLayer::GeometryLayer, true);
  TEST(!IsProtectedAreaFill(regular), ());
  TEST(IsProtectedAreaFill(protectedFill), ());
  TEST_EQUAL(GetDepthLayer(protectedFill), DepthLayer::GeometryLayer, ());
  TEST(regular != protectedFill, ());
  // The batcher uses an ordered map: equality alone would not prevent the two fills being batched together.
  TEST_EQUAL((std::set<dp::RenderState>{regular, protectedFill}).size(), 2, ());

  RenderGroupComparator compare;
  TileKey const tile(0, 0, 14);
  auto const group = [&tile](gpu::Program program, bool isProtected = false)
  { return make_unique_dp<RenderGroup>(CreateRenderState(program, DepthLayer::GeometryLayer, isProtected), tile); };
  for (auto const fill :
       {gpu::Program::Area, gpu::Program::AreaStipple, gpu::Program::AreaSpeckle, gpu::Program::AreaGrid})
    for (auto const overlay : {gpu::Program::Line, gpu::Program::DashedLine, gpu::Program::TransparentArea,
                               gpu::Program::HatchingArea, gpu::Program::HatchingAreaDash})
    {
      auto const protectedGroup = group(fill, true);
      auto const overlayGroup = group(overlay);
      TEST(compare(protectedGroup, overlayGroup), (std::string{DebugPrint(fill)}, std::string{DebugPrint(overlay)}));
      TEST(!compare(overlayGroup, protectedGroup), ());
    }
  // Protected hatching retains its original position before the wetland hatch as well.
  auto const protectedGroup = group(gpu::Program::HatchingArea, true);
  auto const wetlandGroup = group(gpu::Program::HatchingAreaDash);
  TEST(compare(protectedGroup, wetlandGroup), ());
}

UNIT_TEST(ProtectedAreaOutline_ExcludesInternalEdgesAndPreservesHoles)
{
  std::array<Point, 4> const outer{{{0, 0}, {4, 0}, {4, 4}, {0, 4}}};
  std::array<Point, 4> const hole{{{1, 1}, {3, 1}, {3, 3}, {1, 3}}};
  std::vector<Point> triangles;
  std::set<OutlineEdge> expected;
  for (size_t i = 0; i < outer.size(); ++i)
  {
    auto const j = (i + 1) % outer.size();
    AppendQuad(triangles, outer[i], outer[j], hole[j], hole[i]);
    expected.insert(MakeEdge(outer[i], outer[j]));
    expected.insert(MakeEdge(hole[i], hole[j]));
  }
  auto const splines = df::BuildAreaOutlineSplines(triangles, {-1, -1, 5, 5});
  TEST_EQUAL(splines.size(), 2, ());
  TEST_EQUAL(OutlineEdges(splines), expected, ());
  for (auto const & spline : splines)
    TEST_EQUAL(spline->GetPath().front(), spline->GetPath().back(), ());

  // Triangle winding and traversal order cannot change the boundary or its deterministic paths.
  std::reverse(triangles.begin(), triangles.end());
  auto const reversed = df::BuildAreaOutlineSplines(triangles, {-1, -1, 5, 5});
  TEST_EQUAL(reversed.size(), splines.size(), ());
  for (size_t i = 0; i < splines.size(); ++i)
    TEST_EQUAL(reversed[i]->GetPath(), splines[i]->GetPath(), ());
}

UNIT_TEST(ProtectedAreaOutline_MultipleComponentsAndTouchingVertices)
{
  std::vector<Point> triangles;
  std::set<OutlineEdge> expected;
  for (Point const & origin : {Point{0, 0}, Point{2, 2}, Point{6, 0}})
  {
    std::array<Point, 4> const ring{{origin, origin + Point{2, 0}, origin + Point{2, 2}, origin + Point{0, 2}}};
    AppendQuad(triangles, ring[0], ring[1], ring[2], ring[3]);
    for (size_t i = 0; i < ring.size(); ++i)
      expected.insert(MakeEdge(ring[i], ring[(i + 1) % ring.size()]));
  }
  TEST_EQUAL(OutlineEdges(df::BuildAreaOutlineSplines(triangles, {-1, -1, 10, 10})), expected, ());
}

UNIT_TEST(ProtectedAreaOutline_ClippingDoesNotInventTileBoundaries)
{
  std::vector<Point> triangles;
  AppendQuad(triangles, {-2, -2}, {2, -2}, {2, 2}, {-2, 2});
  // A tile wholly inside the reserve has fill, but no boundary of its own.
  TEST(df::BuildAreaOutlineSplines(triangles, {-1, -1, 1, 1}).empty(), ());

  std::set<OutlineEdge> const strip{{MakeEdge({-1, -2}, {1, -2}), MakeEdge({-1, 2}, {1, 2})}};
  TEST_EQUAL(OutlineEdges(df::BuildAreaOutlineSplines(triangles, {-1, -3, 1, 3})), strip, ());

  // Adjacent tiles meet on x=0. Neither may acquire a vertical outline along that seam.
  std::set<OutlineEdge> const left{
      {MakeEdge({-2, -2}, {0, -2}), MakeEdge({-2, -2}, {-2, 2}), MakeEdge({-2, 2}, {0, 2})}};
  std::set<OutlineEdge> const right{{MakeEdge({0, -2}, {2, -2}), MakeEdge({2, -2}, {2, 2}), MakeEdge({0, 2}, {2, 2})}};
  TEST_EQUAL(OutlineEdges(df::BuildAreaOutlineSplines(triangles, {-2, -2, 0, 2})), left, ());
  TEST_EQUAL(OutlineEdges(df::BuildAreaOutlineSplines(triangles, {0, -2, 2, 2})), right, ());
  TEST(df::BuildAreaOutlineSplines(triangles, {5, 5, 6, 6}).empty(), ());
}

UNIT_TEST(ProtectedAreaOutline_LargeMeshAndDegenerateTriangles)
{
  size_t constexpr kSide = 128;
  std::vector<Point> triangles;
  triangles.reserve(kSide * kSide * 6);
  for (size_t x = 0; x < kSide; ++x)
    for (size_t y = 0; y < kSide; ++y)
    {
      Point const origin{static_cast<double>(x), static_cast<double>(y)};
      AppendQuad(triangles, origin, origin + Point{1, 0}, origin + Point{1, 1}, origin + Point{0, 1});
    }
  triangles.insert(triangles.end(), {{1, 1}, {1, 1}, {1, 1}, {2, 2}, {3, 3}, {4, 4}});
  auto const splines = df::BuildAreaOutlineSplines(triangles, {-1, -1, kSide + 1, kSide + 1});
  TEST_EQUAL(splines.size(), 1, ());
  TEST_EQUAL(splines.front()->GetSize(), kSide * 4 + 1, ());
  TEST_EQUAL(OutlineEdges(splines).size(), kSide * 4, ());
  TEST(df::BuildAreaOutlineSplines({}, {-1, -1, 1, 1}).empty(), ());
}

UNIT_CLASS_TEST(VisualParamsFixture, ProtectedAreaOutline_IndependentOfFillGeometryAndOpacity)
{
  df::ApplyFeatureParams params;
  params.Init(df::TileKey(0, 0, 14));
  params.m_tileRect = {-2, -2, 2, 2};
  df::TMapShapes shapes;
  params.m_insertShape = [&shapes](drape_ptr<df::MapShape> && shape) { shapes.push_back(std::move(shape)); };
  FeatureType feature(FeatureID{}, 0);
  df::CaptionDescription const captions;
  drule::LineRule outline;
  outline.width = 3;
  outline.priority = drule::kBasePriorityFg;
  drule::AreaRule fill;
  fill.priority = drule::kBasePriorityBgTop;
  df::Stylist stylist;
  stylist.m_areaRule = &fill;
  stylist.m_isProtectedAreaFill = true;

  for (float const opacity : {0.0f, 1.0f})
  {
    df::ApplyAreaFeature apply(params, feature, captions, false, false, 0, 0, opacity, true);
    apply({-1, -1}, {1, -1}, {1, 1});
    apply({-1, -1}, {1, 1}, {-1, 1});
    TEST_EQUAL(apply.HasGeometry(), opacity > 0, (opacity));
    if (opacity > 0)
    {
      apply.ProcessAreaRules(stylist, {}, {});
      TEST_EQUAL(shapes.size(), 1, ());
      TEST(dynamic_cast<df::AreaShape *>(shapes.front().get()) != nullptr, ());
      shapes.clear();
    }

    // Satellite opacity=0 produces a border without a fill; normal fills can also consume their
    // triangle vector before the independent border is emitted and later hidden by the 2 km cutoff.
    apply.ProcessAreaOutlines({&outline});
    TEST_EQUAL(shapes.size(), 1, (opacity));
    TEST(dynamic_cast<df::LineShape *>(shapes.front().get()) != nullptr, (opacity));
    shapes.clear();
  }
  TEST(!df::IsProtectedAreaFill(df::CreateRenderState(gpu::Program::Line, df::DepthLayer::GeometryLayer)), ());
}
