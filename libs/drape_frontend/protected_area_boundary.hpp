#pragma once

#include <algorithm>
#include <cstddef>
#include <functional>
#include <unordered_map>
#include <utility>
#include <vector>

namespace df
{
// Extracts only real polygon edges from the uncut MWM triangulation. Clipping triangles first
// would turn tile cuts into artificial reserve boundaries. The collector retains only edges
// intersecting the current tile, so a country-sized polygon does not allocate a whole mesh per tile.
class ProtectedAreaBoundary
{
public:
  struct Point
  {
    double x = 0.0;
    double y = 0.0;
    bool operator==(Point const &) const = default;
  };

  using Path = std::vector<Point>;

  ProtectedAreaBoundary(double minX, double minY, double maxX, double maxY)
    : m_minX(minX)
    , m_minY(minY)
    , m_maxX(maxX)
    , m_maxY(maxY)
  {}

  void AddTriangle(Point const & a, Point const & b, Point const & c)
  {
    if ((b.x - a.x) * (c.y - a.y) == (b.y - a.y) * (c.x - a.x))
      return;
    AddEdge(a, b);
    AddEdge(b, c);
    AddEdge(c, a);
  }

  // Boundary components are stitched into open tile-clipped paths or closed rings. Both outer
  // rings and holes have multiplicity-one edges. Shared triangulation edges have multiplicity >=2.
  std::vector<Path> GetPaths() const
  {
    std::vector<Edge> edges;
    edges.reserve(m_edges.size());
    for (auto const & [edge, repeated] : m_edges)
    {
      if (repeated)
        continue;
      Edge clipped = edge;
      if (Clip(clipped.a, clipped.b))
        edges.push_back(clipped);
    }

    std::unordered_map<Point, std::vector<size_t>, PointHash> adjacent;
    adjacent.reserve(edges.size());
    for (size_t i = 0; i < edges.size(); ++i)
    {
      adjacent[edges[i].a].push_back(i);
      adjacent[edges[i].b].push_back(i);
    }

    std::vector<bool> visited(edges.size(), false);
    std::vector<Path> paths;
    auto walk = [&](size_t first, Point start)
    {
      Path path{start};
      size_t index = first;
      while (!visited[index])
      {
        visited[index] = true;
        auto const & edge = edges[index];
        Point const next = edge.a == start ? edge.b : edge.a;
        path.push_back(next);
        if (next == path.front())
          break;
        auto const & choices = adjacent.at(next);
        if (choices.size() != 2)
          break;
        size_t const candidate = choices[0] == index ? choices[1] : choices[0];
        if (visited[candidate])
          break;
        start = next;
        index = candidate;
      }
      paths.push_back(std::move(path));
    };

    // Open paths and non-manifold junctions start at a degree !=2 endpoint. Remaining edges form rings.
    for (size_t i = 0; i < edges.size(); ++i)
    {
      if (visited[i])
        continue;
      if (adjacent.at(edges[i].a).size() != 2)
        walk(i, edges[i].a);
      else if (adjacent.at(edges[i].b).size() != 2)
        walk(i, edges[i].b);
    }
    for (size_t i = 0; i < edges.size(); ++i)
      if (!visited[i])
        walk(i, edges[i].a);
    return paths;
  }

  size_t GetTrackedEdgeCount() const { return m_edges.size(); }

private:
  struct PointHash
  {
    size_t operator()(Point const & point) const
    {
      size_t const x = std::hash<double>{}(point.x);
      size_t const y = std::hash<double>{}(point.y);
      return x ^ (y + size_t{0x9e3779b9} + (x << 6) + (x >> 2));
    }
  };

  struct Edge
  {
    Point a;
    Point b;
    bool operator==(Edge const &) const = default;
  };

  struct EdgeHash
  {
    size_t operator()(Edge const & edge) const
    {
      size_t const a = PointHash{}(edge.a);
      size_t const b = PointHash{}(edge.b);
      return a ^ (b + size_t{0x9e3779b9} + (a << 6) + (a >> 2));
    }
  };

  static bool Less(Point const & a, Point const & b) { return a.x < b.x || (a.x == b.x && a.y < b.y); }

  // Liang-Barsky clipping. Keys are counted before clipping: two different mesh edges which happen
  // to clip onto the same tile edge must never cancel each other or create a fabricated tile rim.
  bool Clip(Point & a, Point & b) const
  {
    double const dx = b.x - a.x;
    double const dy = b.y - a.y;
    double low = 0.0;
    double high = 1.0;
    auto test = [&](double direction, double distance)
    {
      if (direction == 0.0)
        return distance >= 0.0;
      double const t = distance / direction;
      if (direction < 0.0)
        low = std::max(low, t);
      else
        high = std::min(high, t);
      return low <= high;
    };
    if (!test(-dx, a.x - m_minX) || !test(dx, m_maxX - a.x) || !test(-dy, a.y - m_minY) || !test(dy, m_maxY - a.y))
      return false;
    Point const origin = a;
    // Keep uncut shared endpoints bit-identical so adjacent boundary segments stitch exactly.
    if (low > 0.0)
      a = {std::clamp(origin.x + low * dx, m_minX, m_maxX), std::clamp(origin.y + low * dy, m_minY, m_maxY)};
    if (high < 1.0)
      b = {std::clamp(origin.x + high * dx, m_minX, m_maxX), std::clamp(origin.y + high * dy, m_minY, m_maxY)};
    return a != b;
  }

  void AddEdge(Point a, Point b)
  {
    if (a == b)
      return;
    Point clippedA = a;
    Point clippedB = b;
    if (!Clip(clippedA, clippedB))
      return;
    if (Less(b, a))
      std::swap(a, b);
    auto const [position, inserted] = m_edges.try_emplace(Edge{a, b}, false);
    if (!inserted)
      position->second = true;  // Saturate: repeated/non-manifold edges are never a boundary.
  }

  double const m_minX;
  double const m_minY;
  double const m_maxX;
  double const m_maxY;
  std::unordered_map<Edge, bool, EdgeHash> m_edges;
};
}  // namespace df
