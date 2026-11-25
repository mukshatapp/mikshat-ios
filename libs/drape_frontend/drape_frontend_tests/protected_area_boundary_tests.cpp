#include "drape_frontend/protected_area_boundary.hpp"

#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>

#if defined(MUKSHAT_BOUNDARY_STANDALONE)
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
using Boundary = df::ProtectedAreaBoundary;
using Point = Boundary::Point;

void Quad(Boundary & boundary, Point a, Point b, Point c, Point d)
{
  boundary.AddTriangle(a, b, c);
  boundary.AddTriangle(a, c, d);
}

void Square(Boundary & boundary, double x, double y, double side)
{
  Quad(boundary, {x, y}, {x + side, y}, {x + side, y + side}, {x, y + side});
}

size_t Edges(std::vector<Boundary::Path> const & paths)
{
  size_t count = 0;
  for (auto const & path : paths)
    count += path.size() - 1;
  return count;
}

bool Segment(Boundary::Path const & path, Point a, Point b)
{
  return path.size() == 2 && ((path[0] == a && path[1] == b) || (path[0] == b && path[1] == a));
}

void Donut(Boundary & boundary)
{
  Point const outer[] = {{0, 0}, {4, 0}, {4, 4}, {0, 4}};
  Point const inner[] = {{1, 1}, {3, 1}, {3, 3}, {1, 3}};
  for (size_t i = 0; i < 4; ++i)
    Quad(boundary, outer[i], outer[(i + 1) % 4], inner[(i + 1) % 4], inner[i]);
}
}  // namespace

UNIT_TEST(ProtectedAreaBoundary_SquareWithoutTriangulationDiagonal)
{
  Boundary boundary(-1, -1, 3, 3);
  Square(boundary, 0, 0, 2);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 1, ());
  TEST_EQUAL(paths[0].size(), 5, ());
  TEST(paths[0].front() == paths[0].back(), ());
  TEST_EQUAL(Edges(paths), 4, ());
}

UNIT_TEST(ProtectedAreaBoundary_WindingAndExactSharedEndpoints)
{
  Boundary boundary(-1, -1, 2, 2);
  boundary.AddTriangle({0.1, 0.1}, {0.9, 0.9}, {0.9, 0.1});
  boundary.AddTriangle({0.1, 0.1}, {0.9, 0.9}, {0.1, 0.9});
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 1, ());
  TEST_EQUAL(Edges(paths), 4, ());
  TEST(paths[0].front() == paths[0].back(), ());
}

UNIT_TEST(ProtectedAreaBoundary_InteriorTileHasNoFabricatedRim)
{
  Boundary boundary(0.25, 0.25, 0.75, 0.75);
  Square(boundary, 0, 0, 1);
  TEST(boundary.GetPaths().empty(), ());
  TEST(boundary.GetTrackedEdgeCount() <= 1, ());
}

UNIT_TEST(ProtectedAreaBoundary_ClipsRealBoundaryOnly)
{
  Boundary boundary(0.5, -0.5, 1.5, 2.5);
  Square(boundary, 0, 0, 2);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 2, ());
  bool bottom = false;
  bool top = false;
  for (auto const & path : paths)
  {
    bottom |= Segment(path, {0.5, 0}, {1.5, 0});
    top |= Segment(path, {0.5, 2}, {1.5, 2});
  }
  TEST(bottom && top, ());
  TEST_EQUAL(Edges(paths), 2, ());
}

UNIT_TEST(ProtectedAreaBoundary_HoleAndOuterRingSurvive)
{
  Boundary boundary(-1, -1, 5, 5);
  Donut(boundary);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 2, ());
  TEST_EQUAL(Edges(paths), 8, ());
  for (auto const & path : paths)
    TEST(path.size() == 5 && path.front() == path.back(), ());
}

UNIT_TEST(ProtectedAreaBoundary_ClipsHoleBoundaryWithoutTileSeams)
{
  Boundary boundary(0.5, 1.5, 1.5, 2.5);
  Donut(boundary);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 1, ());
  TEST(Segment(paths[0], {1, 1.5}, {1, 2.5}), ());
}

UNIT_TEST(ProtectedAreaBoundary_MultipleHoles)
{
  Boundary boundary(-1, -1, 6, 6);
  for (int x = 0; x < 5; ++x)
    for (int y = 0; y < 5; ++y)
      if (!(x == 1 && y == 1) && !(x == 3 && y == 3))
        Square(boundary, x, y, 1);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 3, ());
  TEST_EQUAL(Edges(paths), 28, ());
  for (auto const & path : paths)
    TEST(path.front() == path.back(), ());
}

UNIT_TEST(ProtectedAreaBoundary_SeparateIslands)
{
  Boundary boundary(-1, -1, 5, 5);
  Square(boundary, 0, 0, 1);
  Square(boundary, 3, 3, 1);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 2, ());
  TEST_EQUAL(Edges(paths), 8, ());
}

UNIT_TEST(ProtectedAreaBoundary_DuplicateAndNonManifoldEdgesNeverBecomeBorders)
{
  Boundary boundary(-1, -1, 2, 2);
  for (int repeat = 0; repeat < 3; ++repeat)
    boundary.AddTriangle({0, 0}, {1, 0}, {0, 1});
  TEST(boundary.GetPaths().empty(), ());
}

UNIT_TEST(ProtectedAreaBoundary_DegenerateTriangles)
{
  Boundary boundary(-1, -1, 2, 2);
  boundary.AddTriangle({0, 0}, {0, 0}, {1, 1});
  boundary.AddTriangle({0, 0}, {0.5, 0.5}, {1, 1});
  TEST_EQUAL(boundary.GetTrackedEdgeCount(), 0, ());
  TEST(boundary.GetPaths().empty(), ());
}

UNIT_TEST(ProtectedAreaBoundary_LongEdgeAndNegativeCoordinates)
{
  Boundary boundary(-1, -1, 1, 1);
  boundary.AddTriangle({0, -100}, {0, 100}, {100, 0});
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 1, ());
  TEST(Segment(paths[0], {0, -1}, {0, 1}), ());
}

UNIT_TEST(ProtectedAreaBoundary_LargeAreaKeepsOnlyTileLocalEdges)
{
  Boundary boundary(199.25, 199.25, 200.75, 200.75);
  for (int x = 0; x < 400; ++x)
    for (int y = 0; y < 400; ++y)
      Square(boundary, x, y, 1);
  TEST(boundary.GetTrackedEdgeCount() < 32, ());
  TEST(boundary.GetPaths().empty(), ());
}

UNIT_TEST(ProtectedAreaBoundary_FullMeshHasOneOuterBoundary)
{
  Boundary boundary(-1, -1, 129, 129);
  for (int x = 0; x < 128; ++x)
    for (int y = 0; y < 128; ++y)
      Square(boundary, x, y, 1);
  auto const paths = boundary.GetPaths();
  TEST_EQUAL(paths.size(), 1, ());
  TEST_EQUAL(Edges(paths), 128 * 4, ());
  TEST(paths[0].front() == paths[0].back(), ());
}

#if defined(MUKSHAT_BOUNDARY_STANDALONE)
int main()
{
  auto const start = std::chrono::steady_clock::now();
  ProtectedAreaBoundary_SquareWithoutTriangulationDiagonal();
  ProtectedAreaBoundary_WindingAndExactSharedEndpoints();
  ProtectedAreaBoundary_InteriorTileHasNoFabricatedRim();
  ProtectedAreaBoundary_ClipsRealBoundaryOnly();
  ProtectedAreaBoundary_HoleAndOuterRingSurvive();
  ProtectedAreaBoundary_ClipsHoleBoundaryWithoutTileSeams();
  ProtectedAreaBoundary_MultipleHoles();
  ProtectedAreaBoundary_SeparateIslands();
  ProtectedAreaBoundary_DuplicateAndNonManifoldEdgesNeverBecomeBorders();
  ProtectedAreaBoundary_DegenerateTriangles();
  ProtectedAreaBoundary_LongEdgeAndNegativeCoordinates();
  ProtectedAreaBoundary_LargeAreaKeepsOnlyTileLocalEdges();
  ProtectedAreaBoundary_FullMeshHasOneOuterBoundary();
  auto const elapsed =
      std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
  std::cout << "PASS: " << checks << " protected-area boundary checks; 13 scenarios; " << elapsed << " ms\n";
}
#endif
